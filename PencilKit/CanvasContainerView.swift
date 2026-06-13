import SwiftUI
import PencilKit

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
        let scrollView = UIScrollView()
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
    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var editor: EditorViewModel
        let autoSave: AutoSaveService
        let controller: CanvasController
        var structureToken: Int = -1

        weak var scrollView: UIScrollView?
        weak var stack: UIStackView?
        private var pageViews: [PageContainerView] = []
        private var pageForCanvas: [ObjectIdentifier: Page] = [:]
        private var didInitialFit = false
        private var requestedNewPage = false

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
                guard let self, self.pageViews.indices.contains(index),
                      let scrollView = self.scrollView else { return }
                // If zoomed far out (e.g. a pinch-out overview), restore a
                // readable full-width zoom before jumping to the page.
                if let fit = self.fitWidthScale(), scrollView.zoomScale < fit * 0.9 {
                    self.applyFit()
                }
                let target = self.pageViews[index]
                let rect = target.convert(target.bounds, to: scrollView)
                scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -28), animated: true)
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

        /// Zooms so the page fills the editor's full width the first time it lays
        /// out (GoodNotes-style: no side dead space; scroll vertically for more).
        func fitToPageIfNeeded() {
            guard !didInitialFit, fitWidthScale() != nil else { return }
            applyFit()
            didInitialFit = true
        }

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

        func rebuild(pages: [Page]) {
            guard let stack else { return }
            pageViews.forEach { $0.removeFromSuperview() }
            pageViews.removeAll()
            pageForCanvas.removeAll()

            for page in pages {
                let pv = PageContainerView(page: page)
                pv.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    pv.widthAnchor.constraint(equalToConstant: page.canvasSize.width),
                    pv.heightAnchor.constraint(equalToConstant: page.canvasSize.height)
                ])
                pv.canvas.delegate = self
                pageForCanvas[ObjectIdentifier(pv.canvas)] = page
                pv.overlay.makeItem = { [weak self] kind, frame, s, e in
                    self?.editor.makeItem(kind: kind, frame: frame, start: s, end: e)
                        ?? CanvasItem(kind: kind, frame: frame, start: s, end: e)
                }
                pv.overlay.onChange = { [weak self, weak page] items in
                    guard let self, let page else { return }
                    page.items = items
                    self.autoSave.scheduleSave(touching: page)
                }
                stack.addArrangedSubview(pv)
                pageViews.append(pv)
            }
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
                // Selection enables the PencilKit lasso (any input) for ink.
                pv.canvas.drawingPolicy = isSelection ? .anyInput : editor.drawingPolicy
                pv.canvas.drawingGestureRecognizer.isEnabled = !isOverlayDraw
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
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let overscroll = bottomOverscroll(scrollView)
            if overscroll > 90 { appendPageOnce() }
            else if overscroll < 20 { requestedNewPage = false }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if bottomOverscroll(scrollView) > 40 { appendPageOnce() }
        }

        private func bottomOverscroll(_ scrollView: UIScrollView) -> CGFloat {
            // Distance pulled up beyond the bottom of the content.
            scrollView.contentOffset.y + scrollView.bounds.height
                - max(scrollView.contentSize.height, scrollView.bounds.height)
        }

        private func appendPageOnce() {
            guard !requestedNewPage else { return }
            requestedNewPage = true
            controller.requestNewPageAtEnd()
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

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let page = pageForCanvas[ObjectIdentifier(canvasView)] else { return }
            page.drawingData = canvasView.drawing.dataRepresentation()
            autoSave.scheduleSave(touching: page)
        }
    }
}
