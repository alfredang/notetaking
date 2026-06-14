import UIKit

/// Interactive vector overlay drawn above a page's PencilKit canvas.
/// Handles shape/flowchart creation and selection (move/resize), and renders
/// items via the shared `PageRenderer` drawing routine.
final class ShapeOverlayView: UIView {
    /// Current items (page coordinates).
    var items: [CanvasItem] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Active tool; controls touch behavior.
    var tool: EditorTool = .pen {
        didSet {
            // Overlay tools draw/select; erasers intercept touches that land on a
            // vector shape so they can delete it (otherwise the eraser only reaches
            // the handwriting layer beneath the overlay).
            isUserInteractionEnabled = tool.isOverlayTool || tool.isEraser
            if !tool.isOverlayTool { selectedIDs.removeAll() }
        }
    }

    /// Builds a styled item for the current tool settings.
    var makeItem: (ShapeKind, CGRect, CGPoint?, CGPoint?) -> CanvasItem = { kind, frame, s, e in
        CanvasItem(kind: kind, frame: frame, start: s, end: e)
    }

    /// Called whenever items change (commit), for persistence.
    var onChange: ([CanvasItem]) -> Void = { _ in }

    /// Asks the host to switch back to the selection tool (e.g. after dropping a
    /// sticky note, so the next tap doesn't create another one).
    var requestSelectionTool: () -> Void = {}

    // Ink (PencilKit) lasso bridge — the canvas owns the strokes, so these
    // closures let the overlay's lasso select/move/recolor/delete ink.
    /// Selects ink strokes enclosed by the polygon; returns their bounding box.
    var selectInk: ([CGPoint]) -> CGRect? = { _ in nil }
    var moveSelectedInk: (CGSize) -> Void = { _ in }
    var recolorSelectedInk: (RGBAColor) -> Void = { _ in }
    var deleteSelectedInk: () -> Void = {}
    var clearInkSelection: () -> Void = {}
    /// Serializes / restores the page's handwriting so ink lasso edits (move /
    /// recolor / delete) join the shared undo timeline alongside shape edits.
    var snapshotInk: () -> Data? = { nil }
    var restoreInk: (Data) -> Void = { _ in }

    /// Currently selected overlay items. A single id → resize handles + move;
    /// several (via lasso) → group move / delete / recolor.
    private(set) var selectedIDs: Set<UUID> = []
    /// The lone selected item's id when exactly one is selected (handles, resize,
    /// tap-to-edit). Nil for an empty or multi-selection.
    private var singleSelectedID: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    /// Whether anything is selected — vector shapes and/or a handwriting (ink)
    /// group. Drives the toolbar's delete/recolor enablement.
    var hasAnySelection: Bool { !selectedIDs.isEmpty || inkSelectionRect != nil }

    /// Undo manager shared with this page's PencilKit canvas, so shape edits and
    /// handwriting interleave on one timeline (set by `PageContainerView`).
    weak var shapeUndoManager: UndoManager?
    /// `items` snapshot captured at the start of a gesture (move / resize / erase
    /// / text edit), registered as a single undo step when the gesture commits.
    private var gestureUndoSnapshot: [CanvasItem]?
    /// Handwriting snapshot captured alongside `gestureUndoSnapshot` when a move
    /// includes selected ink, so the move undoes both layers together.
    private var gestureInkSnapshot: Data?
    /// Per-item geometry captured at the start of a group move.
    private var moveOriginals: [UUID: CanvasItem] = [:]
    /// `items` snapshot captured when inline text editing begins, so the whole
    /// edit (text + any fill change) collapses into one undo step.
    private var textUndoSnapshot: [CanvasItem]?

    /// Bounding box of a lasso-selected ink group (nil when none).
    private var inkSelectionRect: CGRect?
    private var inkSelected: Bool { inkSelectionRect != nil }
    private var lastDragPoint: CGPoint = .zero

    // Interaction state
    private var draft: CanvasItem?
    private var dragStart: CGPoint = .zero
    private enum DragMode { case none, create, move, resize(handle: Int), lasso, erase }
    private var dragMode: DragMode = .none
    private var movingItemOriginalFrame: CGRect = .zero
    private var lassoPoints: [CGPoint] = []

    private let handleSize: CGFloat = 22
    private var didMove = false
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    /// Applies a color picked from the system color wheel to the active selection.
    private var pendingColorApply: ((RGBAColor) -> Void)?

    // Inline text editor (type directly into a sticky note / labelled shape).
    private weak var activeTextView: UITextView?
    private var editingItemID: UUID?
    private var editingIsNode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        addInteraction(editMenuInteraction)

        // Double-tap a labelled item (sticky note / flowchart node) to edit its text.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // Press-and-hold any item (notably a sticky note, whose tap opens the text
        // editor) to bring up the edit menu — change background color / delete.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)
    }

    /// Press-and-hold: select the pressed item and pop up its edit menu.
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, tool == .selection, activeTextView == nil else { return }
        let point = gesture.location(in: self)
        guard let item = items.last(where: { hitTest($0, point: point) }) else { return }
        clearInkSelectionState()
        selectedIDs = [item.id]
        dragMode = .none
        setNeedsDisplay()
        presentEditMenu(at: CGPoint(x: item.frame.midX, y: item.frame.minY - 8))
    }

    /// Shows a popup (delete / duplicate / change color) next to a selection.
    private func presentEditMenu(at point: CGPoint) {
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
        editMenuInteraction.presentEditMenu(with: config)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Whether a finger may draw/select on the overlay. When false the overlay
    /// lets finger touches fall through so a single finger scrolls the page.
    var allowsFingerDrawing = false

    /// Controls which touches the overlay intercepts so finger-scroll and
    /// two-finger zoom keep working in every tool:
    /// - selection: only items/handles (empty space → canvas lasso for ink),
    /// - shape/flowchart: the Pencil draws; a finger falls through to scroll
    ///   (unless finger drawing is enabled).
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return false }
        // While inline-editing, capture taps outside the text view so they
        // commit and exit edit mode.
        if activeTextView != nil { return true }
        let isFinger = (event?.allTouches?.first?.type ?? .pencil) != .pencil
        switch tool {
        case .selection:
            // The Pencil selects / moves / draws the lasso loop (and can select
            // handwriting ink so we show our own recolor / move / delete menu). A
            // finger falls through so one finger scrolls the page and two fingers
            // pinch-zoom — matching draw mode. With finger drawing on, the finger
            // selects instead (panning then needs two fingers).
            if isFinger && !allowsFingerDrawing { return false }
            return true
        case .shape, .flowchart:
            if isFinger && !allowsFingerDrawing { return false }
            return super.point(inside: point, with: event)
        case .eraserPixel, .eraserObject:
            // Erase whole vector shapes on contact. Empty space falls through so
            // the PencilKit canvas still erases handwriting; a finger keeps panning.
            if isFinger && !allowsFingerDrawing { return false }
            return items.contains { hitTest($0, point: point) }
        default:
            return false
        }
    }

    /// Recolors every selected item's stroke (and fill if it has one), plus any
    /// selected handwriting ink — one undo step for the whole mixed selection.
    func setSelectedColor(_ color: RGBAColor) {
        let hasShapes = !selectedIDs.isEmpty
        let hasInk = inkSelectionRect != nil
        guard hasShapes || hasInk else { return }
        let beforeItems = items
        let beforeInk = hasInk ? snapshotInk() : nil
        if hasShapes {
            for i in items.indices where selectedIDs.contains(items[i].id) {
                items[i].strokeColor = color
                if items[i].fillColor.alpha > 0 { items[i].fillColor = color }
            }
        }
        if hasInk { recolorSelectedInk(color) }
        registerSelectionUndo(items: beforeItems, ink: beforeInk)
        onChange(items)
        setNeedsDisplay()
    }

    /// Sets the background (fill) of the selected labelled items and picks a
    /// readable text/border color (dark on light fills, light on dark fills).
    func setSelectedFill(_ color: RGBAColor) {
        guard !selectedIDs.isEmpty else { return }
        let before = items
        let lum = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        let stroke: RGBAColor = lum > 0.6
            ? RGBAColor(red: 0.12, green: 0.12, blue: 0.12)
            : RGBAColor(red: 1, green: 1, blue: 1)
        for i in items.indices where selectedIDs.contains(items[i].id) {
            items[i].fillColor = color
            items[i].strokeColor = stroke
        }
        commitChange(from: before)
    }

    // MARK: - Undo support

    /// Records the change from `before` to the current `items` as one undo step
    /// (on the shared page undo manager), then persists.
    private func commitChange(from before: [CanvasItem]) {
        if before != items { registerUndo(previous: before) }
        onChange(items)
        setNeedsDisplay()
    }

    /// Registers a snapshot-restoring undo (and its mirror redo) on the shared
    /// undo manager so shape edits reverse alongside handwriting strokes.
    private func registerUndo(previous: [CanvasItem]) {
        guard let um = shapeUndoManager else { return }
        um.registerUndo(withTarget: self) { target in
            let redoSnapshot = target.items
            target.items = previous
            target.selectedIDs.removeAll()
            target.clearInkSelectionState()
            target.onChange(target.items)
            target.setNeedsDisplay()
            target.registerUndo(previous: redoSnapshot)
        }
    }

    /// Registers a combined undo that restores both layers — vector `items` and
    /// the handwriting `ink` (when supplied) — for mixed-selection edits
    /// (delete / recolor / group move). Re-registers its mirror as a redo.
    private func registerSelectionUndo(items beforeItems: [CanvasItem], ink beforeInk: Data?) {
        guard let um = shapeUndoManager else { return }
        um.registerUndo(withTarget: self) { target in
            let redoItems = target.items
            let redoInk = target.snapshotInk()
            target.items = beforeItems
            if let beforeInk { target.restoreInk(beforeInk) }
            target.selectedIDs.removeAll()
            target.inkSelectionRect = nil
            target.onChange(target.items)
            target.setNeedsDisplay()
            target.registerSelectionUndo(items: redoItems, ink: redoInk)
        }
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        var renderItems = items
        if let draft { renderItems.append(draft) }
        PageRenderer.drawOverlay(items: renderItems, in: ctx)

        if let id = singleSelectedID, let selected = items.first(where: { $0.id == id }) {
            drawSelection(for: selected, in: ctx)
        } else if selectedIDs.count > 1 {
            for item in items where selectedIDs.contains(item.id) {
                drawGroupSelection(box: itemBounds(item), in: ctx)
            }
        }

        // Dashed box around a lasso-selected handwriting group.
        if let r = inkSelectionRect {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(r.insetBy(dx: -6, dy: -6))
            ctx.restoreGState()
        }

        if case .lasso = dragMode, lassoPoints.count > 1 {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.beginPath()
            ctx.move(to: lassoPoints[0])
            for p in lassoPoints.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Dashed outline (no handles) for one member of a multi-selection.
    private func drawGroupSelection(box: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(box.insetBy(dx: -4, dy: -4))
        ctx.restoreGState()
    }

    /// Tight bounding box of an item (handles line-like items whose `frame` is zero).
    private func itemBounds(_ item: CanvasItem) -> CGRect {
        if item.kind.isLineLike {
            return CGRect(x: min(item.start.x, item.end.x), y: min(item.start.y, item.end.y),
                          width: abs(item.end.x - item.start.x), height: abs(item.end.y - item.start.y))
        }
        return item.frame
    }

    private func drawSelection(for item: CanvasItem, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(item.frame.insetBy(dx: -4, dy: -4))
        ctx.setLineDash(phase: 0, lengths: [])
        for handle in handleRects(for: item) {
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.fillEllipse(in: handle)
            ctx.strokeEllipse(in: handle)
        }
        ctx.restoreGState()
    }

    /// Corner handles for rect shapes; endpoint handles for line-like items.
    private func handleRects(for item: CanvasItem) -> [CGRect] {
        let points: [CGPoint]
        if item.kind.isLineLike {
            points = [item.start, item.end]
        } else {
            let f = item.frame
            points = [
                CGPoint(x: f.minX, y: f.minY),
                CGPoint(x: f.maxX, y: f.minY),
                CGPoint(x: f.maxX, y: f.maxY),
                CGPoint(x: f.minX, y: f.maxY)
            ]
        }
        return points.map { CGRect(x: $0.x - handleSize / 2, y: $0.y - handleSize / 2, width: handleSize, height: handleSize) }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A tap outside the active text view commits it and exits edit mode.
        if activeTextView != nil {
            finishTextEditing()
            return
        }
        guard let point = touches.first?.location(in: self) else { return }
        dragStart = point

        switch tool {
        case .shape(let kind), .flowchart(let kind):
            dragMode = .create
            draft = makeItem(kind, CGRect(origin: point, size: .zero), point, point)
        case .selection:
            beginSelectionTouch(at: point)
        case .eraserPixel, .eraserObject:
            dragMode = .erase
            gestureUndoSnapshot = items
            eraseItem(at: point)
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        switch dragMode {
        case .create:
            updateDraft(to: point)
        case .move:
            didMove = true
            // Shapes translate from their captured originals (absolute delta);
            // selected ink translates incrementally — both move as one group.
            moveSelected(by: CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y))
            if inkSelectionRect != nil {
                let d = CGSize(width: point.x - lastDragPoint.x, height: point.y - lastDragPoint.y)
                moveSelectedInk(d)
                inkSelectionRect = inkSelectionRect?.offsetBy(dx: d.width, dy: d.height)
            }
            lastDragPoint = point
        case .resize(let handle):
            didMove = true
            resizeSelected(handle: handle, to: point)
        case .lasso:
            lassoPoints.append(point)
        case .erase:
            eraseItem(at: point)
        case .none:
            break
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch dragMode {
        case .create:
            commitDraft()
        case .resize:
            rerouteConnectors()
            if didMove, let before = gestureUndoSnapshot { registerUndo(previous: before) }
            onChange(items)
            moveOriginals = [:]
            gestureUndoSnapshot = nil
        case .move:
            rerouteConnectors()
            // One undo step restores both layers (shapes + ink) for a group move.
            if didMove { registerSelectionUndo(items: gestureUndoSnapshot ?? items, ink: gestureInkSnapshot) }
            onChange(items)
            moveOriginals = [:]
            gestureUndoSnapshot = nil
            gestureInkSnapshot = nil
            // A tap (no drag) on a single shape: labelled items open their text
            // editor; other shapes show the edit menu (delete / color / duplicate).
            if !didMove, let id = singleSelectedID, let sel = items.first(where: { $0.id == id }) {
                if sel.kind.hasLabel {
                    beginTextEditing(for: sel.id)
                } else {
                    presentEditMenu(at: CGPoint(x: sel.frame.midX, y: sel.frame.minY - 8))
                }
            }
        case .lasso:
            finishLasso()
        case .erase:
            // Items were removed + persisted live in eraseItem; record one undo
            // step for the whole erase stroke.
            if let before = gestureUndoSnapshot, before != items { registerUndo(previous: before) }
            gestureUndoSnapshot = nil
        case .none:
            break
        }
        didMove = false
        dragMode = .none
        draft = nil
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragMode = .none
        draft = nil
        lassoPoints = []
        didMove = false
        setNeedsDisplay()
    }

    // MARK: - Creation

    private func updateDraft(to point: CGPoint) {
        guard var d = draft else { return }
        if d.kind.isLineLike {
            d.end = point
        } else {
            d.frame = CGRect(
                x: min(dragStart.x, point.x),
                y: min(dragStart.y, point.y),
                width: abs(point.x - dragStart.x),
                height: abs(point.y - dragStart.y)
            )
        }
        draft = d
    }

    private func commitDraft() {
        guard var d = draft else { return }
        let before = items
        // Discard tiny accidental taps.
        let minimal: CGFloat = 8
        if d.kind.isLineLike {
            if hypot(d.end.x - d.start.x, d.end.y - d.start.y) < minimal { draft = nil; return }
            // Snap connector endpoints to nearby nodes.
            if d.kind == .connector {
                if let src = node(near: d.start) { d.sourceItemID = src.id; d.start = anchor(on: src, toward: d.end) }
                if let dst = node(near: d.end) { d.targetItemID = dst.id; d.end = anchor(on: dst, toward: d.start) }
            }
        } else if d.frame.width < minimal && d.frame.height < minimal {
            // A tap (no real drag): drop a default-sized card for flowchart nodes
            // and labelled items, otherwise discard the accidental dot.
            guard d.kind.hasLabel || d.kind.isNode else { draft = nil; return }
            let size = defaultSize(for: d.kind)
            d.frame = CGRect(x: dragStart.x, y: dragStart.y, width: size.width, height: size.height)
        }
        items.append(d)
        selectedIDs = [d.id]
        commitChange(from: before)

        // After placing a sticky note, leave create-mode and open its editor so
        // the user can type immediately with the keyboard.
        // Sticky notes and flowchart nodes (process / decision / start-end) drop
        // straight into inline text editing, then leave create-mode.
        if d.kind.hasLabel {
            requestSelectionTool()
            beginTextEditing(for: d.id)
        }
    }

    /// Default footprint for a tapped (not dragged) labelled item.
    private func defaultSize(for kind: ShapeKind) -> CGSize {
        switch kind {
        case .stickyNote: return CGSize(width: 160, height: 160)
        case .decision, .preparation, .offPageConnector: return CGSize(width: 160, height: 100)
        case .database, .document, .manualInput, .manualOperation: return CGSize(width: 150, height: 110)
        case .connectorNode: return CGSize(width: 56, height: 56)
        default: return CGSize(width: 160, height: 72)
        }
    }

    // MARK: - Text editing

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let item = items.last(where: { $0.kind.hasLabel && hitTest($0, point: point) }) else { return }
        beginTextEditing(for: item.id)
    }

    // MARK: - Inline text editing

    /// Shows an editable, multi-line text view positioned over a labelled item
    /// so the user types directly into the note (no popup dialog).
    func beginTextEditing(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        textUndoSnapshot = items
        activeTextView?.resignFirstResponder()

        let hasFill = item.fillColor.alpha > 0
        let bg: UIColor = hasFill ? item.fillColor.uiColor : .white
        let lum = hasFill
            ? 0.299 * item.fillColor.red + 0.587 * item.fillColor.green + 0.114 * item.fillColor.blue
            : 1.0
        let textColor: UIColor = lum > 0.6 ? UIColor(white: 0.12, alpha: 1) : .white

        let tv = UITextView(frame: item.frame.insetBy(dx: 4, dy: 4))
        tv.delegate = self
        tv.font = .systemFont(ofSize: 17, weight: .medium)
        tv.textColor = textColor
        tv.tintColor = textColor
        tv.backgroundColor = bg
        // Pin to light so system colors never render dark on the white page.
        tv.overrideUserInterfaceStyle = .light
        tv.layer.cornerRadius = 6
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.autocapitalizationType = .sentences
        tv.isScrollEnabled = true
        tv.text = (item.text == item.kind.defaultLabel) ? "" : (item.text ?? "")

        // Flowchart nodes center their text (matching the rendered node);
        // sticky notes keep top-left.
        editingIsNode = item.kind.isNode
        if editingIsNode { tv.textAlignment = .center }

        tv.inputAccessoryView = makeEditingAccessory()

        addSubview(tv)
        activeTextView = tv
        editingItemID = id
        tv.becomeFirstResponder()
        tv.layoutIfNeeded()
        centerTextVerticallyIfNeeded()
        setNeedsDisplay()
    }

    /// Vertically centers a flowchart node's text within the editor.
    private func centerTextVerticallyIfNeeded() {
        guard editingIsNode, let tv = activeTextView else { return }
        let top = max(8, (tv.bounds.height - tv.contentSize.height) / 2)
        tv.textContainerInset = UIEdgeInsets(top: top, left: 6, bottom: 8, right: 6)
    }

    @objc private func finishTextEditing() {
        activeTextView?.resignFirstResponder()
    }

    /// Sets the background (fill) color of the element being edited, and picks a
    /// readable text/border color (dark on light fills, light on dark fills).
    private func setEditingItemFill(_ color: RGBAColor) {
        guard let id = editingItemID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let lum = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        let textColor: RGBAColor = lum > 0.6
            ? RGBAColor(red: 0.12, green: 0.12, blue: 0.12)
            : RGBAColor(red: 1, green: 1, blue: 1)
        items[idx].fillColor = color
        items[idx].strokeColor = textColor
        activeTextView?.backgroundColor = color.uiColor
        activeTextView?.textColor = textColor.uiColor
        activeTextView?.tintColor = textColor.uiColor
        onChange(items)
        setNeedsDisplay()
    }

    /// Keyboard-accessory toolbar with a background-color menu and Done.
    private func makeEditingAccessory() -> UIToolbar {
        let bar = UIToolbar()
        let colorActions = zip(ToolDefaults.extendedPalette,
                               ["Black", "Dark Gray", "Gray", "Light Gray", "Silver", "White",
                                "Dark Red", "Red", "Salmon", "Pink", "Magenta", "Purple",
                                "Brown", "Dark Orange", "Orange", "Amber", "Yellow", "Lime",
                                "Dark Green", "Green", "Emerald", "Teal",
                                "Blue", "Indigo", "Sky", "Navy"])
            .map { color, name in
                UIAction(title: name, image: ShapeOverlayView.swatch(color.uiColor)) { [weak self] _ in
                    self?.setEditingItemFill(color)
                }
            }
        let colorMenu = UIMenu(title: "Background Color", children: colorActions)
        let colorItem = UIBarButtonItem(title: "Background",
                                        image: UIImage(systemName: "paintpalette"), menu: colorMenu)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(finishTextEditing))
        bar.items = [colorItem, UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        bar.sizeToFit()
        return bar
    }

    // MARK: - Selection

    private func beginSelectionTouch(at point: CGPoint) {
        // Resize handle of a single selected shape (only when no ink is in the mix)?
        if let id = singleSelectedID, inkSelectionRect == nil,
           let selected = items.first(where: { $0.id == id }) {
            for (i, handle) in handleRects(for: selected).enumerated() where handle.contains(point) {
                dragMode = .resize(handle: i)
                movingItemOriginalFrame = selected.frame
                gestureUndoSnapshot = items
                return
            }
        }
        // Tapping anywhere within the current selection — a selected shape or
        // inside the ink box — drags the whole selection (shapes + handwriting).
        let onSelectedShape = items.contains { selectedIDs.contains($0.id) && hitTest($0, point: point) }
        let onInkSelection = inkSelectionRect?.insetBy(dx: -8, dy: -8).contains(point) ?? false
        if hasAnySelection, onSelectedShape || onInkSelection {
            beginSelectionMove(at: point)
            return
        }
        // Otherwise: tapping an unselected shape selects & moves just it; empty
        // space starts a lasso loop (selecting shapes and/or handwriting ink).
        if let hit = items.last(where: { hitTest($0, point: point) }) {
            clearInkSelectionState()
            selectedIDs = [hit.id]
            beginSelectionMove(at: point)
        } else {
            selectedIDs.removeAll()
            clearInkSelectionState()
            lassoPoints = [point]
            dragMode = .lasso
        }
        setNeedsDisplay()
    }

    /// Begins dragging the current selection (any mix of shapes + ink), capturing
    /// the snapshots needed for a single combined undo step.
    private func beginSelectionMove(at point: CGPoint) {
        moveOriginals = Dictionary(uniqueKeysWithValues:
            items.filter { selectedIDs.contains($0.id) }.map { ($0.id, $0) })
        lastDragPoint = point
        gestureUndoSnapshot = items
        gestureInkSnapshot = (inkSelectionRect != nil) ? snapshotInk() : nil
        dragMode = .move
    }

    /// Drops any active handwriting (ink) lasso selection.
    private func clearInkSelectionState() {
        guard inkSelectionRect != nil else { return }
        inkSelectionRect = nil
        clearInkSelection()
    }

    /// Selects the topmost item enclosed by the lasso loop and pops up its menu.
    private func finishLasso() {
        defer { lassoPoints = [] }
        guard lassoPoints.count > 2 else { return }
        let poly = lassoPoints
        // Select every enclosed shape AND the handwriting ink the loop encloses,
        // so one lasso can grab a mix of both types (and overlapping shapes).
        let hits = items.filter { enclosed($0, in: poly) }
        selectedIDs = Set(hits.map { $0.id })
        let inkRect = selectInk(poly)        // also sets/clears the ink stroke selection
        inkSelectionRect = inkRect
        guard !hits.isEmpty || inkRect != nil else { return }
        var box = hits.reduce(CGRect.null) { $0.union(itemBounds($1)) }
        if let inkRect { box = box.union(inkRect) }
        setNeedsDisplay()
        presentEditMenu(at: CGPoint(x: box.midX, y: box.minY - 8))
    }

    private func enclosed(_ item: CanvasItem, in polygon: [CGPoint]) -> Bool {
        let pts: [CGPoint]
        if item.kind.isLineLike {
            pts = [item.start, item.end,
                   CGPoint(x: (item.start.x + item.end.x) / 2, y: (item.start.y + item.end.y) / 2)]
        } else {
            pts = [CGPoint(x: item.frame.midX, y: item.frame.midY)]
        }
        return pts.contains { pointInPolygon($0, polygon) }
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if ((a.y > p.y) != (b.y > p.y)),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func hitTest(_ item: CanvasItem, point: CGPoint) -> Bool {
        if item.kind.isLineLike {
            return distance(point, segment: (item.start, item.end)) < 14
        }
        return item.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    /// Removes the topmost vector item under `point` (and any flowchart
    /// connectors bound to it). Drives the eraser tools, which otherwise only
    /// affect the PencilKit handwriting layer beneath the overlay.
    private func eraseItem(at point: CGPoint) {
        // Remove every item under the point (not just the topmost) so the eraser
        // clears overlapping shapes, plus any connector bound to a removed node.
        let hitIDs = Set(items.filter { hitTest($0, point: point) }.map { $0.id })
        guard !hitIDs.isEmpty else { return }
        items.removeAll { hitIDs.contains($0.id)
            || ($0.sourceItemID.map(hitIDs.contains) ?? false)
            || ($0.targetItemID.map(hitIDs.contains) ?? false) }
        onChange(items)
        setNeedsDisplay()
    }

    private func moveSelected(by delta: CGPoint) {
        for i in items.indices {
            guard let original = moveOriginals[items[i].id] else { continue }
            if items[i].kind.isLineLike {
                items[i].start = CGPoint(x: original.start.x + delta.x, y: original.start.y + delta.y)
                items[i].end = CGPoint(x: original.end.x + delta.x, y: original.end.y + delta.y)
            } else {
                items[i].frame = original.frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        rerouteConnectors()
    }

    private func resizeSelected(handle: Int, to point: CGPoint) {
        guard let id = singleSelectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if items[idx].kind.isLineLike {
            if handle == 0 { items[idx].start = point } else { items[idx].end = point }
        } else {
            var f = movingItemOriginalFrame
            switch handle {
            case 0: f = CGRect(x: point.x, y: point.y, width: f.maxX - point.x, height: f.maxY - point.y)
            case 1: f = CGRect(x: f.minX, y: point.y, width: point.x - f.minX, height: f.maxY - point.y)
            case 2: f = CGRect(x: f.minX, y: f.minY, width: point.x - f.minX, height: point.y - f.minY)
            default: f = CGRect(x: point.x, y: f.minY, width: f.maxX - point.x, height: point.y - f.minY)
            }
            items[idx].frame = f.standardized
        }
        rerouteConnectors()
    }

    // MARK: - Public selection actions

    func deleteSelected() {
        let hasShapes = !selectedIDs.isEmpty
        let hasInk = inkSelectionRect != nil
        guard hasShapes || hasInk else { return }
        let beforeItems = items
        let beforeInk = hasInk ? snapshotInk() : nil
        if hasShapes {
            let ids = selectedIDs
            // Remove the selected items plus any connector bound to one of them.
            items.removeAll { ids.contains($0.id)
                || ($0.sourceItemID.map(ids.contains) ?? false)
                || ($0.targetItemID.map(ids.contains) ?? false) }
        }
        if hasInk {
            deleteSelectedInk()
            clearInkSelectionState()
        }
        selectedIDs.removeAll()
        registerSelectionUndo(items: beforeItems, ink: beforeInk)
        onChange(items)
        setNeedsDisplay()
    }

    func duplicateSelected() {
        guard !selectedIDs.isEmpty else { return }
        let before = items
        var newIDs = Set<UUID>()
        for item in items where selectedIDs.contains(item.id) {
            var copy = item
            copy.id = UUID()
            copy.frame = item.frame.offsetBy(dx: 24, dy: 24)
            if item.kind.isLineLike {
                copy.start = CGPoint(x: item.start.x + 24, y: item.start.y + 24)
                copy.end = CGPoint(x: item.end.x + 24, y: item.end.y + 24)
            }
            copy.sourceItemID = nil
            copy.targetItemID = nil
            items.append(copy)
            newIDs.insert(copy.id)
        }
        selectedIDs = newIDs
        commitChange(from: before)
    }

    // MARK: - Flowchart connector routing

    /// Re-anchors connectors bound to nodes so they follow the nodes when moved.
    private func rerouteConnectors() {
        for i in items.indices where items[i].kind == .connector {
            if let sid = items[i].sourceItemID, let node = items.first(where: { $0.id == sid }) {
                items[i].start = anchor(on: node, toward: items[i].end)
            }
            if let tid = items[i].targetItemID, let node = items.first(where: { $0.id == tid }) {
                items[i].end = anchor(on: node, toward: items[i].start)
            }
        }
    }

    private func node(near point: CGPoint) -> CanvasItem? {
        items.last { $0.kind.isNode && $0.frame.insetBy(dx: -12, dy: -12).contains(point) }
    }

    /// The point on a node's bounding box edge in the direction of `target`.
    private func anchor(on node: CanvasItem, toward target: CGPoint) -> CGPoint {
        let c = node.center
        let dx = target.x - c.x
        let dy = target.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let hw = node.frame.width / 2
        let hh = node.frame.height / 2
        let scale = 1 / max(abs(dx) / max(hw, 1), abs(dy) / max(hh, 1))
        return CGPoint(x: c.x + dx * scale, y: c.y + dy * scale)
    }

    // MARK: - Geometry helpers

    private func distance(_ p: CGPoint, segment: (CGPoint, CGPoint)) -> CGFloat {
        let (a, b) = segment
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}

// MARK: - Inline text editing

extension ShapeOverlayView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        centerTextVerticallyIfNeeded()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if let id = editingItemID, let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].text = textView.text
            if let before = textUndoSnapshot, before != items { registerUndo(previous: before) }
            onChange(items)
        }
        textUndoSnapshot = nil
        textView.removeFromSuperview()
        activeTextView = nil
        editingItemID = nil
        setNeedsDisplay()
    }
}

// MARK: - Selection edit menu (delete / duplicate / change color)

extension ShapeOverlayView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        // One unified menu for any selection — vector shapes, handwriting ink, or
        // a mix of both. Delete and color apply across every selected element.
        let hasShapes = !selectedIDs.isEmpty
        let hasInk = inkSelectionRect != nil
        guard hasShapes || hasInk else { return nil }

        // A lone sticky note / flowchart node recolors its *background* (fill) with
        // a readable text color; everything else (plain shapes, multi-selections,
        // ink) recolors stroke/ink.
        let labelled = !hasInk && (singleSelectedID
            .flatMap { id in items.first { $0.id == id }?.kind.hasLabel } ?? false)
        let apply: (RGBAColor) -> Void = labelled
            ? { [weak self] c in self?.setSelectedFill(c) }
            : { [weak self] c in self?.setSelectedColor(c) }

        let colorActions = ToolDefaults.extendedPalette.map { color in
            UIAction(title: "", image: ShapeOverlayView.swatch(color.uiColor)) { _ in
                apply(color)
            }
        }
        // Inline + .small lays the swatches out as a grid, like the toolbar's
        // color dropdown.
        let palette = UIMenu(title: labelled ? "Background Color" : "Color",
                             options: .displayInline, children: colorActions)
        palette.preferredElementSize = .small
        let custom = UIAction(title: "Custom…", image: UIImage(systemName: "eyedropper")) { [weak self] _ in
            self?.presentCustomColorPicker(current: .black) { c in apply(c) }
        }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak self] _ in
            self?.deleteSelected()
        }
        var children: [UIMenuElement] = [delete]
        // Duplicate only applies to vector shapes (ink duplication isn't supported).
        if hasShapes {
            let duplicate = UIAction(title: "Duplicate",
                                     image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                self?.duplicateSelected()
            }
            children.append(duplicate)
        }
        children.append(contentsOf: [palette, custom])
        return UIMenu(children: children)
    }

    /// A small filled-circle image used as a color menu swatch (with a hairline
    /// border so white / light colors stay visible on the menu background).
    private static func swatch(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            color.setFill()
            ctx.cgContext.fillEllipse(in: rect)
            UIColor.separator.setStroke()
            ctx.cgContext.setLineWidth(1)
            ctx.cgContext.strokeEllipse(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - Custom color picker (system color wheel for arbitrary colors)

extension ShapeOverlayView: UIColorPickerViewControllerDelegate {
    /// Presents the system color picker; the chosen color is applied via `apply`.
    func presentCustomColorPicker(current: UIColor, apply: @escaping (RGBAColor) -> Void) {
        guard let vc = nearestViewController() else { return }
        pendingColorApply = apply
        let picker = UIColorPickerViewController()
        picker.selectedColor = current
        picker.supportsAlpha = false
        picker.delegate = self
        vc.present(picker, animated: true)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                   didSelect color: UIColor, continuously: Bool) {
        pendingColorApply?(ShapeOverlayView.rgba(from: color))
        setNeedsDisplay()
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        pendingColorApply = nil
    }

    private static func rgba(from c: UIColor) -> RGBAColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBAColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
}
