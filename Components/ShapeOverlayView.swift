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

    private(set) var selectedID: UUID?

    // Interaction state
    private var draft: CanvasItem?
    private var dragStart: CGPoint = .zero
    private enum DragMode { case none, create, move, resize(handle: Int) }
    private var dragMode: DragMode = .none
    private var movingItemOriginalFrame: CGRect = .zero

    private let handleSize: CGFloat = 22

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw

        // Double-tap a labelled item (sticky note / flowchart node) to edit its text.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        var renderItems = items
        if let draft { renderItems.append(draft) }
        PageRenderer.drawOverlay(items: renderItems, in: ctx)

        if let selected = items.first(where: { $0.id == selectedID }) {
            drawSelection(for: selected, in: ctx)
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
            moveSelected(by: CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y))
        case .resize(let handle):
            resizeSelected(handle: handle, to: point)
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
        case .none:
            break
        }
        dragMode = .none
        draft = nil
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragMode = .none
        draft = nil
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
        presentTextEditor(for: item.id, current: item.text ?? "")
    }

    private func presentTextEditor(for id: UUID, current: String) {
        // Walk the responder chain to find a view controller to present from.
        var responder: UIResponder? = self
        while let r = responder, !(r is UIViewController) { responder = r.next }
        guard let presenter = responder as? UIViewController else { return }

        let alert = UIAlertController(title: "Edit Text", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = current
            tf.placeholder = "Text"
            tf.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            guard let self, let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[idx].text = alert.textFields?.first?.text ?? ""
            self.selectedID = id
            self.onChange(self.items)
            self.setNeedsDisplay()
        })
        presenter.present(alert, animated: true)
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
        // Hit-test items top-down.
        if let hit = items.last(where: { hitTest($0, point: point) }) {
            selectedID = hit.id
            movingItemOriginalFrame = hit.frame
            dragMode = .move
        } else {
            selectedID = nil
            dragMode = .none
        }
        setNeedsDisplay()
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
