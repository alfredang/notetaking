import SwiftUI
import PencilKit

/// Scroll view that reports size changes so the editor can re-fit the page to
/// the available width (on open and on rotation / multitasking resize).
final class EditorScrollView: UIScrollView {
    var onBoundsChange: ((CGSize) -> Void)?
    private var lastSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onBoundsChange?(bounds.size)
        }
    }
}

/// SwiftUI wrapper around a zoom/pan `UIScrollView` that stacks the notebook's
/// pages vertically. Pencil draws on each page's canvas; fingers pan/zoom.
struct CanvasContainerView: UIViewRepresentable {
    let pages: [Page]
    @Bindable var editor: EditorViewModel
    let autoSave: AutoSaveService
    /// Bumped when the page set changes (add/delete/reorder/clear) to force rebuild.
    let structureToken: Int
    /// Changes whenever a tool/ink setting changes; the host view reads it so
    /// SwiftUI re-renders and `updateUIView` pushes the new tool to the canvas.
    let toolStateToken: String
    /// Lets the toolbar drive imperative selection actions on the overlays.
    let controller: CanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, autoSave: autoSave, controller: controller)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = EditorScrollView()
        scrollView.onBoundsChange = { [weak coordinator = context.coordinator] _ in
            coordinator?.handleBoundsChange()
        }
        // Canvas surround adapts to light/dark mode (light gray vs near-black),
        // while the page paper and ink stay literal (see PageContainerView).
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.minimumZoomScale = 0.15
        scrollView.maximumZoomScale = 5.0
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        // Only a finger pans/scrolls — the Apple Pencil is reserved for drawing
        // and creating shapes (otherwise the scroll pan steals the Pencil drag).
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]

        // Double-tap (or squeeze) on the Apple Pencil toggles the tool palette.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        scrollView.addInteraction(pencilInteraction)

        // Double-tap with a finger to zoom into the tapped page (and back out).
        let doubleTapZoom = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTapZoom(_:)))
        doubleTapZoom.numberOfTapsRequired = 2
        doubleTapZoom.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTapZoom)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.stack = stack
        context.coordinator.rebuild(pages: pages)
        context.coordinator.applyTool()
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.editor = editor
        if context.coordinator.structureToken != structureToken {
            context.coordinator.structureToken = structureToken
            context.coordinator.rebuild(pages: pages)
        }
        context.coordinator.applyTool()
        context.coordinator.fitToPageIfNeeded()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate,
                             UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var editor: EditorViewModel
        let autoSave: AutoSaveService
        let controller: CanvasController
        var structureToken: Int = -1

        weak var scrollView: UIScrollView?
        weak var stack: UIStackView?
        private var pageViews: [PageContainerView] = []
        private var pageForCanvas: [ObjectIdentifier: Page] = [:]
        private var didInitialFit = false
        private var autoFitScale: CGFloat = 0
        private var requestedNewPage = false
        private var requestedNewPageTop = false
        private var thumbnailRefreshTask: Task<Void, Never>?

        init(editor: EditorViewModel, autoSave: AutoSaveService, controller: CanvasController) {
            self.editor = editor
            self.autoSave = autoSave
            self.controller = controller
            super.init()
            wireController()
        }

        private func wireController() {
            controller.deleteSelection = { [weak self] in
                self?.pageViews.first { $0.overlay.selectedID != nil }?.overlay.deleteSelected()
            }
            controller.duplicateSelection = { [weak self] in
                self?.pageViews.first { $0.overlay.selectedID != nil }?.overlay.duplicateSelected()
            }
            controller.hasSelection = { [weak self] in
                self?.pageViews.contains { $0.overlay.selectedID != nil } ?? false
            }
            controller.reload = { [weak self] page in
                self?.pageViews.first { $0.page.id == page.id }?.reloadFromModel()
            }
            controller.reloadAllPages = { [weak self] in
                self?.pageViews.forEach { $0.reloadFromModel() }
            }
            // Undo/redo act on the canvas the user is currently viewing. Each
            // canvas owns its own UndoManager (see StrokeCanvasView), so this
            // reliably reverses the strokes drawn on that page.
            controller.undo = { [weak self] in
                let canvas = self?.mostVisiblePageView()?.canvas
                if canvas?.undoManager?.canUndo == true { canvas?.undoManager?.undo() }
            }
            controller.redo = { [weak self] in
                let canvas = self?.mostVisiblePageView()?.canvas
                if canvas?.undoManager?.canRedo == true { canvas?.undoManager?.redo() }
            }
            controller.setZoom = { [weak self] scale in
                self?.scrollView?.setZoomScale(scale, animated: true)
            }
            controller.scrollToPage = { [weak self] index in
                // Defer to the next runloop so a just-added page view is built
                // and laid out — otherwise its frame is (0,0) and we'd scroll to
                // the top (the first page) instead of the target.
                DispatchQueue.main.async {
                    guard let self, self.pageViews.indices.contains(index),
                          let scrollView = self.scrollView else { return }
                    if let fit = self.fitWidthScale(), scrollView.zoomScale < fit * 0.9 {
                        self.applyFit()
                    }
                    scrollView.layoutIfNeeded()
                    let target = self.pageViews[index]
                    let rect = target.convert(target.bounds, to: scrollView)
                    scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -28), animated: true)
                }
            }
            controller.currentVisiblePage = { [weak self] in self?.mostVisiblePageView()?.page }
            controller.clearVisiblePage = { [weak self] in self?.clearVisiblePage() }
            controller.clearAllPages = { [weak self] in self?.clearAllPages() }
            controller.applyTool = { [weak self] in self?.applyTool() }
            controller.setSelectedColor = { [weak self] color in
                self?.pageViews.first { $0.overlay.selectedID != nil }?.overlay.setSelectedColor(color)
            }
        }

        /// Clears the on-screen canvas + overlay for the visible page and persists it.
        private func clearVisiblePage() {
            guard let pv = mostVisiblePageView() else { return }
            clear(pv)
            autoSave.saveNow()
        }

        /// Clears every page's on-screen canvas + overlay and persists.
        private func clearAllPages() {
            for pv in pageViews { clear(pv) }
            autoSave.saveNow()
        }

        private func clear(_ pv: PageContainerView) {
            pv.canvas.drawing = PKDrawing()
            pv.canvas.undoManager?.removeAllActions()
            pv.overlay.items = []
            pv.page.drawingData = Data()
            pv.page.shapesData = Data()
            pv.page.touch()
        }

        /// On open, fit the page to the full width and show the top of the first
        /// page. On rotation / resize, re-fit if the user hasn't manually zoomed.
        func handleBoundsChange() {
            guard let scrollView, let fit = fitWidthScale() else { return }
            if !didInitialFit {
                applyFit()
                scrollToTop()
                didInitialFit = true
                autoFitScale = fit
            } else if abs(scrollView.zoomScale - autoFitScale) < 0.02 {
                applyFit()
                autoFitScale = scrollView.zoomScale
            }
        }

        private func scrollToTop() {
            guard let scrollView else { return }
            scrollView.setContentOffset(
                CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top),
                animated: false)
        }

        func fitToPageIfNeeded() { handleBoundsChange() }

        /// The zoom scale that makes the page fill the editor's width.
        private func fitWidthScale() -> CGFloat? {
            guard let scrollView, let pv = pageViews.first else { return nil }
            let bounds = scrollView.bounds.size
            guard bounds.width > 1, bounds.height > 1 else { return nil }
            let sidePadding: CGFloat = 16 // 8pt leading + 8pt trailing
            let scale = (bounds.width - sidePadding) / pv.page.canvasSize.width
            return max(scrollView.minimumZoomScale, min(scrollView.maximumZoomScale, scale))
        }

        private func applyFit() {
            guard let scrollView, let scale = fitWidthScale() else { return }
            scrollView.setZoomScale(scale, animated: false)
            editor.zoomScale = scale
            centerContent()
        }

        /// Finger double-tap: zoom into the tapped page, or back out to fit.
        /// Scoped to drawing tools so it doesn't clash with the overlay's
        /// double-tap-to-edit-text in selection/shape modes.
        @objc func handleDoubleTapZoom(_ gesture: UITapGestureRecognizer) {
            guard !editor.tool.isOverlayTool,
                  let scrollView, let stack, let fit = fitWidthScale() else { return }
            if scrollView.zoomScale > fit * 1.05 {
                scrollView.setZoomScale(fit, animated: true)
            } else {
                let target = min(scrollView.maximumZoomScale, fit * 2)
                let center = gesture.location(in: stack)
                let size = CGSize(width: scrollView.bounds.width / target,
                                  height: scrollView.bounds.height / target)
                let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        /// The page view occupying the most of the scroll view's viewport.
        private func mostVisiblePageView() -> PageContainerView? {
            guard let scrollView else { return pageViews.first }
            let visible = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
            var best: (view: PageContainerView, area: CGFloat)?
            for pv in pageViews {
                let frame = pv.convert(pv.bounds, to: scrollView)
                let overlap = frame.intersection(visible)
                guard !overlap.isNull else { continue }
                let area = overlap.width * overlap.height
                if best == nil || area > best!.area { best = (pv, area) }
            }
            return best?.view ?? pageViews.first
        }

        /// Incremental rebuild: reuse existing page views (preserving their
        /// PKCanvasView state, undo, and scroll position) and only create views
        /// for new pages. Recreating every PKCanvasView on each change is what
        /// made adding/clearing pages lag.
        func rebuild(pages: [Page]) {
            guard let stack else { return }
            var existing: [UUID: PageContainerView] = [:]
            for pv in pageViews { existing[pv.page.id] = pv }

            var result: [PageContainerView] = []
            for page in pages {
                if let pv = existing.removeValue(forKey: page.id) {
                    result.append(pv)
                } else {
                    result.append(makePageView(page))
                }
            }
            // Remove views for pages that no longer exist.
            for pv in existing.values {
                pageForCanvas[ObjectIdentifier(pv.canvas)] = nil
                pv.removeFromSuperview()
            }
            // Arrange in order, reusing/moving existing views (no full teardown).
            for (i, pv) in result.enumerated() {
                if !(stack.arrangedSubviews.indices.contains(i) && stack.arrangedSubviews[i] === pv) {
                    stack.insertArrangedSubview(pv, at: i)
                }
                pv.updateFooter() // refresh page number after insert/delete/reorder
            }
            pageViews = result
        }

        /// Builds and wires a fresh page view (used for new pages only).
        private func makePageView(_ page: Page) -> PageContainerView {
            let pv = PageContainerView(page: page)
            pv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pv.widthAnchor.constraint(equalToConstant: page.canvasSize.width),
                pv.heightAnchor.constraint(equalToConstant: page.canvasSize.height)
            ])
            pv.canvas.delegate = self
            pageForCanvas[ObjectIdentifier(pv.canvas)] = page

            // "Draw a line, then hold the end" → snap the stroke straight.
            let holdStill = HoldStillGestureRecognizer(
                target: self, action: #selector(handleStraightenHold(_:)))
            holdStill.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            holdStill.cancelsTouchesInView = false
            holdStill.delaysTouchesEnded = false
            holdStill.delegate = self
            pv.canvas.addGestureRecognizer(holdStill)
            pv.overlay.makeItem = { [weak self] kind, frame, s, e in
                self?.editor.makeItem(kind: kind, frame: frame, start: s, end: e)
                    ?? CanvasItem(kind: kind, frame: frame, start: s, end: e)
            }
            pv.overlay.onChange = { [weak self, weak page] items in
                guard let self, let page else { return }
                page.items = items
                self.autoSave.scheduleSave(touching: page)
            }
            pv.overlay.requestSelectionTool = { [weak self] in
                self?.editor.tool = .selection
                self?.applyTool()
            }
            // Handwriting (ink) lasso bridge: the canvas owns the strokes, so the
            // overlay's lasso defers stroke selection / recolor / move / delete here.
            pv.overlay.selectInk = { [weak pv] poly in pv?.selectInk(in: poly) }
            pv.overlay.clearInkSelection = { [weak pv] in pv?.clearInkSelection() }
            pv.overlay.recolorSelectedInk = { [weak self, weak pv, weak page] rgba in
                guard let pv, let page else { return }
                pv.recolorSelectedInk(rgba.uiColor)
                self?.persistInk(of: pv, page: page)
            }
            pv.overlay.moveSelectedInk = { [weak self, weak pv, weak page] offset in
                guard let pv, let page else { return }
                pv.moveSelectedInk(by: offset)
                self?.persistInk(of: pv, page: page)
            }
            pv.overlay.deleteSelectedInk = { [weak self, weak pv, weak page] in
                guard let pv, let page else { return }
                pv.deleteSelectedInk()
                self?.persistInk(of: pv, page: page)
            }
            return pv
        }

        /// Persists a page's handwriting after an ink-bridge edit (recolor/move/delete).
        private func persistInk(of pv: PageContainerView, page: Page) {
            page.drawingData = pv.canvas.drawing.dataRepresentation()
            autoSave.scheduleSave(touching: page)
        }

        /// Applies the current tool to every page's canvas + overlay.
        func applyTool() {
            let tool = editor.tool
            let isSelection = (tool == .selection)
            let isOverlayDraw: Bool = {
                switch tool { case .shape, .flowchart: return true; default: return false }
            }()

            // Two fingers ALWAYS pinch-zoom. A single finger scrolls in every
            // tool except selection (where it draws the lasso loop). The Apple
            // Pencil draws / selects via the overlay or canvas.
            scrollView?.pinchGestureRecognizer?.isEnabled = true
            scrollView?.isScrollEnabled = !isSelection
            // With finger drawing on, a single finger draws so panning needs two
            // fingers; otherwise a single finger scrolls.
            scrollView?.panGestureRecognizer.minimumNumberOfTouches =
                editor.allowsFingerDrawing ? 2 : 1

            for pv in pageViews {
                pv.canvas.tool = editor.pkTool
                pv.canvas.drawingPolicy = editor.drawingPolicy
                // In selection mode the overlay owns the lasso (it can recolor ink),
                // so the canvas's own drawing/lasso gesture is disabled.
                pv.canvas.drawingGestureRecognizer.isEnabled = !(isOverlayDraw || isSelection)
                pv.overlay.tool = tool
                pv.overlay.allowsFingerDrawing = editor.allowsFingerDrawing
            }
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { stack }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Re-center live during the pinch, but defer the observable zoom
            // update to the end so the toolbar/zoom label don't re-render every
            // frame (which caused flicker and dropped taps).
            centerContent()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            editor.zoomScale = scale
        }

        /// Keeps the page(s) centered when zoomed out smaller than the viewport
        /// (otherwise the content pins to the top-left, leaving dead space).
        private func centerContent() {
            guard let scrollView else { return }
            let h = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let v = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: v, left: h, bottom: 0, right: h)
        }

        /// Swiping up past the end of the last page appends a new blank page
        /// (continuous, GoodNotes-style paging).
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // One page per drag gesture: only re-arm when a new drag starts.
            requestedNewPage = false
            requestedNewPageTop = false
        }

        /// A new page is created only on a deliberate pull-and-release: the user
        /// must drag well past the edge (against the rubber-band resistance) and
        /// lift. A casual scroll or flick won't reach the threshold, so it never
        /// spawns stray blank pages.
        private let pullThreshold: CGFloat = 130

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if bottomOverscroll(scrollView) > pullThreshold { appendPageOnce() }
            if topOverscroll(scrollView) > pullThreshold { prependPageOnce() }
        }

        private func bottomOverscroll(_ scrollView: UIScrollView) -> CGFloat {
            // Distance pulled up beyond the bottom of the content.
            scrollView.contentOffset.y + scrollView.bounds.height
                - max(scrollView.contentSize.height, scrollView.bounds.height)
        }

        private func topOverscroll(_ scrollView: UIScrollView) -> CGFloat {
            // Distance pulled down beyond the top of the content.
            -(scrollView.contentOffset.y + scrollView.contentInset.top)
        }

        private func appendPageOnce() {
            guard !requestedNewPage else { return }
            requestedNewPage = true
            controller.requestNewPageAtEnd()
        }

        private func prependPageOnce() {
            guard !requestedNewPageTop else { return }
            requestedNewPageTop = true
            controller.requestNewPageAtStart()
        }

        // MARK: UIPencilInteractionDelegate

        /// Apple Pencil double-tap / squeeze — hides or shows the tool palette
        /// when the user has enabled that gesture in Settings (default on).
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            togglePaletteIfEnabled()
        }

        private func togglePaletteIfEnabled() {
            let enabled = UserDefaults.standard.object(forKey: "pencilDoubleTapHidesPalette") as? Bool ?? true
            guard enabled else { return }
            editor.isPaletteHidden.toggle()
        }

        // MARK: PKCanvasViewDelegate

        /// While the Pencil is actively drawing, disable scrolling so a resting
        /// palm can't pan the page (palm rejection for the scroll view; PencilKit
        /// already rejects the palm for drawing).
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // A genuine user edit is starting — make sure a load that never echoed
            // can't suppress this stroke's timestamp update.
            if let canvas = canvasView as? StrokeCanvasView {
                canvas.loadingDrawing = false
                canvas.isDrawingStroke = true
                canvas.straightenArmed = false
            }
            scrollView?.isScrollEnabled = false
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            (canvasView as? StrokeCanvasView)?.isDrawingStroke = false
            applyTool() // restores scrolling appropriately for the current tool
        }

        // MARK: Hold-to-straighten

        /// Arms straightening when the Pencil holds still at the end of a stroke.
        @objc func handleStraightenHold(_ gesture: HoldStillGestureRecognizer) {
            guard gesture.state == .began,
                  editor.tool.isInking,
                  let canvas = gesture.view as? StrokeCanvasView,
                  canvas.isDrawingStroke else { return }
            canvas.straightenArmed = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        /// Let the hold-still recognizer coexist with PencilKit's drawing gesture.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gestureRecognizer is HoldStillGestureRecognizer
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Ignore the echo of a programmatic drawing load (open / reload): it is
            // not a user edit, so it must not stamp the page's updatedAt.
            if let canvas = canvasView as? StrokeCanvasView, canvas.loadingDrawing {
                canvas.loadingDrawing = false
                return
            }
            guard let page = pageForCanvas[ObjectIdentifier(canvasView)] else { return }

            // If the user held still at the end of this stroke, snap it straight.
            if let canvas = canvasView as? StrokeCanvasView, canvas.straightenArmed {
                canvas.straightenArmed = false
                if let straightened = StrokeStraightener.straightenLast(in: canvasView.drawing) {
                    canvas.loadingDrawing = true // ignore the echo from this programmatic set
                    canvasView.drawing = straightened
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }

            page.drawingData = canvasView.drawing.dataRepresentation()
            autoSave.scheduleSave(touching: page)   // touches updatedAt synchronously
            pageViews.first { $0.canvas === canvasView }?.updateFooter()
            scheduleThumbnailRefresh()
        }

        /// Refreshes sidebar thumbnails a moment after drawing stops (so they
        /// reflect the latest content without re-rendering on every stroke).
        private func scheduleThumbnailRefresh() {
            thumbnailRefreshTask?.cancel()
            thumbnailRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.7))
                if Task.isCancelled { return }
                self?.controller.refreshThumbnails()
            }
        }
    }
}
