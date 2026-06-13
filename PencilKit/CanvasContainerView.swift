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
    /// Lets the toolbar drive imperative selection actions on the overlays.
    let controller: CanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, autoSave: autoSave, controller: controller)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 5.0
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28)
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
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        var editor: EditorViewModel
        let autoSave: AutoSaveService
        let controller: CanvasController
        var structureToken: Int = -1

        weak var scrollView: UIScrollView?
        weak var stack: UIStackView?
        private var pageViews: [PageContainerView] = []
        private var pageForCanvas: [ObjectIdentifier: Page] = [:]

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
            controller.undo = { [weak self] in self?.scrollView?.undoManager?.undo() }
            controller.redo = { [weak self] in self?.scrollView?.undoManager?.redo() }
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

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let page = pageForCanvas[ObjectIdentifier(canvasView)] else { return }
            page.drawingData = canvasView.drawing.dataRepresentation()
            autoSave.scheduleSave(touching: page)
        }
    }
}
