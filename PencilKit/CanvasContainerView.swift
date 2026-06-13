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
        scrollView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        scrollView.minimumZoomScale = 0.15
        scrollView.maximumZoomScale = 5.0
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        // Double-tap (or squeeze) on the Apple Pencil toggles the tool palette.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        scrollView.addInteraction(pencilInteraction)

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
                let target = self.pageViews[index]
                let rect = target.convert(target.bounds, to: scrollView)
                scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -28), animated: true)
            }
            controller.currentVisiblePage = { [weak self] in self?.mostVisiblePageView()?.page }
            controller.clearVisiblePage = { [weak self] in self?.clearVisiblePage() }
            controller.clearAllPages = { [weak self] in self?.clearAllPages() }
            controller.applyTool = { [weak self] in self?.applyTool() }
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
            guard !didInitialFit, let scrollView, let pv = pageViews.first else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width > 1, bounds.height > 1 else { return }
            let pageSize = pv.page.canvasSize
            let sidePadding: CGFloat = 16 // 8pt leading + 8pt trailing
            let scale = (bounds.width - sidePadding) / pageSize.width
            let clamped = max(scrollView.minimumZoomScale, min(scrollView.maximumZoomScale, scale))
            scrollView.setZoomScale(clamped, animated: false)
            editor.zoomScale = clamped
            didInitialFit = true
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
            let isOverlay = tool.isOverlayTool
            scrollView?.isScrollEnabled = !isOverlay
            scrollView?.pinchGestureRecognizer?.isEnabled = !isOverlay
            // When finger drawing is enabled a single finger must DRAW, not pan —
            // otherwise the scroll view's pan gesture steals the touch from the
            // canvas and nothing gets inked. Require two fingers to pan in that
            // mode; with Pencil-only drawing a single finger keeps panning.
            scrollView?.panGestureRecognizer.minimumNumberOfTouches =
                (editor.allowsFingerDrawing && !isOverlay) ? 2 : 1

            for pv in pageViews {
                pv.canvas.tool = editor.pkTool
                pv.canvas.drawingPolicy = editor.drawingPolicy
                pv.canvas.drawingGestureRecognizer.isEnabled = !isOverlay
                pv.overlay.tool = tool
            }
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { stack }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            editor.zoomScale = scrollView.zoomScale
        }

        /// Swiping up past the end of the last page appends a new blank page
        /// (continuous, GoodNotes-style paging).
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.contentSize.height > scrollView.bounds.height else { return }
            let overscroll = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.contentSize.height
            if overscroll > 130, !requestedNewPage {
                requestedNewPage = true
                controller.requestNewPageAtEnd()
            } else if overscroll < 30 {
                requestedNewPage = false
            }
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
