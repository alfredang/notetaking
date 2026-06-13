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
        didSet { isUserInteractionEnabled = tool.isOverlayTool; if !tool.isOverlayTool { selectedID = nil } }
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

    private(set) var selectedID: UUID?
    /// Bounding box of a lasso-selected ink group (nil when none).
    private var inkSelectionRect: CGRect?
    private var inkSelected: Bool { inkSelectionRect != nil }
    private var lastDragPoint: CGPoint = .zero

    // Interaction state
    private var draft: CanvasItem?
    private var dragStart: CGPoint = .zero
    private enum DragMode { case none, create, move, moveInk, resize(handle: Int), lasso }
    private var dragMode: DragMode = .none
    private var movingItemOriginalFrame: CGRect = .zero
    private var lassoPoints: [CGPoint] = []

    private let handleSize: CGFloat = 22
    private var didMove = false
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

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
            // Intercept everything in selection mode: taps on shapes/handles and
            // empty-space lasso loops (which now select handwriting ink in the
            // overlay so we can show our own recolor / move / delete menu). Page
            // scroll is disabled in selection mode, and two-finger pinch-zoom still
            // works via the scroll view's own gesture recognizer.
            return true
        case .shape, .flowchart:
            if isFinger && !allowsFingerDrawing { return false }
            return super.point(inside: point, with: event)
        default:
            return false
        }
    }

    /// Recolors the currently selected item's stroke (and fill if it has one).
    func setSelectedColor(_ color: RGBAColor) {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].strokeColor = color
        if items[idx].fillColor.alpha > 0 { items[idx].fillColor = color }
        onChange(items)
        setNeedsDisplay()
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        var renderItems = items
        if let draft { renderItems.append(draft) }
        PageRenderer.drawOverlay(items: renderItems, in: ctx)

        if let selected = items.first(where: { $0.id == selectedID }) {
            drawSelection(for: selected, in: ctx)
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
            moveSelected(by: CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y))
        case .moveInk:
            didMove = true
            let d = CGSize(width: point.x - lastDragPoint.x, height: point.y - lastDragPoint.y)
            moveSelectedInk(d)
            inkSelectionRect = inkSelectionRect?.offsetBy(dx: d.width, dy: d.height)
            lastDragPoint = point
        case .resize(let handle):
            didMove = true
            resizeSelected(handle: handle, to: point)
        case .lasso:
            lassoPoints.append(point)
        case .none:
            break
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch dragMode {
        case .create:
            commitDraft()
        case .move, .resize:
            rerouteConnectors()
            onChange(items)
            // A tap (no drag) on an item: labelled items open their text editor;
            // other shapes show the edit menu (delete / color / duplicate).
            if !didMove, let sel = items.first(where: { $0.id == selectedID }) {
                if sel.kind.hasLabel {
                    beginTextEditing(for: sel.id)
                } else {
                    presentEditMenu(at: CGPoint(x: sel.frame.midX, y: sel.frame.minY - 8))
                }
            }
        case .moveInk:
            break   // strokes were moved + persisted live via the ink bridge
        case .lasso:
            finishLasso()
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
            // A tap (no real drag): drop a default-sized card for labelled items,
            // otherwise discard the accidental dot.
            guard d.kind.hasLabel else { draft = nil; return }
            let size = defaultSize(for: d.kind)
            d.frame = CGRect(x: dragStart.x, y: dragStart.y, width: size.width, height: size.height)
        }
        items.append(d)
        selectedID = d.id
        onChange(items)

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
        case .decision: return CGSize(width: 160, height: 100)
        default: return CGSize(width: 160, height: 64)
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
        tv.text = (item.text == defaultLabel(for: item.kind)) ? "" : (item.text ?? "")

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

    /// Default placeholder text per kind (so it isn't shown as real content).
    private func defaultLabel(for kind: ShapeKind) -> String {
        switch kind {
        case .process: "Process"
        case .decision: "Decision"
        case .startEnd: "Start"
        case .stickyNote: "Note"
        default: ""
        }
    }

    // MARK: - Selection

    private func beginSelectionTouch(at point: CGPoint) {
        // Resize handle of currently selected item?
        if let selected = items.first(where: { $0.id == selectedID }) {
            for (i, handle) in handleRects(for: selected).enumerated() where handle.contains(point) {
                dragMode = .resize(handle: i)
                movingItemOriginalFrame = selected.frame
                return
            }
        }
        // Inside an existing ink selection? Drag to move the selected strokes.
        if let rect = inkSelectionRect, rect.insetBy(dx: -8, dy: -8).contains(point) {
            dragMode = .moveInk
            lastDragPoint = point
            return
        }
        // Hit-test items top-down.
        if let hit = items.last(where: { hitTest($0, point: point) }) {
            clearInkSelectionState()
            selectedID = hit.id
            movingItemOriginalFrame = hit.frame
            dragMode = .move
        } else {
            // Empty space: begin a lasso loop (selects a shape, or failing that the
            // handwriting strokes it encloses).
            selectedID = nil
            clearInkSelectionState()
            lassoPoints = [point]
            dragMode = .lasso
        }
        setNeedsDisplay()
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
        // Prefer a fully enclosed shape; otherwise select the handwriting ink.
        if let hit = items.last(where: { enclosed($0, in: poly) }) {
            selectedID = hit.id
            presentEditMenu(at: CGPoint(x: hit.frame.midX, y: hit.frame.minY - 8))
            return
        }
        selectedID = nil
        if let rect = selectInk(poly) {
            inkSelectionRect = rect
            setNeedsDisplay()
            presentEditMenu(at: CGPoint(x: rect.midX, y: rect.minY - 8))
        }
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

    private func moveSelected(by delta: CGPoint) {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if items[idx].kind.isLineLike {
            items[idx].start = CGPoint(x: items[idx].start.x + delta.x, y: items[idx].start.y + delta.y)
            items[idx].end = CGPoint(x: items[idx].end.x + delta.x, y: items[idx].end.y + delta.y)
        } else {
            items[idx].frame = movingItemOriginalFrame.offsetBy(dx: delta.x, dy: delta.y)
        }
        rerouteConnectors()
    }

    private func resizeSelected(handle: Int, to point: CGPoint) {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
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
        guard let id = selectedID else { return }
        items.removeAll { $0.id == id || $0.sourceItemID == id || $0.targetItemID == id }
        selectedID = nil
        onChange(items)
        setNeedsDisplay()
    }

    func duplicateSelected() {
        guard let id = selectedID, let item = items.first(where: { $0.id == id }) else { return }
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
        selectedID = copy.id
        onChange(items)
        setNeedsDisplay()
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
            onChange(items)
        }
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
        // Handwriting (ink) selection: recolor or delete the lasso group.
        if selectedID == nil, inkSelectionRect != nil {
            let names = ["Black", "Blue", "Red", "Green", "Orange", "Purple", "Yellow", "Gray"]
            let colorActions = zip(ToolDefaults.palette, names).map { color, name in
                UIAction(title: name, image: ShapeOverlayView.swatch(color.uiColor)) { [weak self] _ in
                    self?.recolorSelectedInk(color)
                    self?.clearInkSelectionState()
                    self?.setNeedsDisplay()
                }
            }
            let colorMenu = UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"),
                                   children: colorActions)
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { [weak self] _ in
                self?.deleteSelectedInk()
                self?.clearInkSelectionState()
                self?.setNeedsDisplay()
            }
            return UIMenu(children: [colorMenu, delete])
        }

        guard selectedID != nil else { return nil }

        let duplicate = UIAction(title: "Duplicate",
                                 image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
            self?.duplicateSelected()
        }
        let colorNames = ["Black", "Blue", "Red", "Green", "Orange", "Purple", "Yellow", "Gray"]
        let colorActions = zip(ToolDefaults.palette, colorNames).map { color, name in
            UIAction(title: name, image: ShapeOverlayView.swatch(color.uiColor)) { [weak self] _ in
                self?.setSelectedColor(color)
            }
        }
        let colorMenu = UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"),
                               children: colorActions)
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak self] _ in
            self?.deleteSelected()
        }
        return UIMenu(children: [duplicate, colorMenu, delete])
    }

    /// A small filled-circle image used as a color menu icon.
    private static func swatch(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 18, height: 18)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }
}
