import SwiftUI

/// The drawing surface: the page canvas with a floating toolbar and zoom controls.
struct EditorView: View {
    let pages: [Page]
    @Bindable var editor: EditorViewModel
    let autoSave: AutoSaveService
    let controller: CanvasController
    let structureToken: Int

    private let zoomPresets: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CanvasContainerView(
                pages: pages,
                editor: editor,
                autoSave: autoSave,
                structureToken: structureToken,
                controller: controller
            )
            .ignoresSafeArea(edges: .bottom)

            ToolbarView(editor: editor, controller: controller)
                .padding(.trailing, 16)
                .padding(.top, 16)

            zoomControls
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                controller.setZoom(max(0.25, editor.zoomScale - 0.25))
            } label: { Image(systemName: "minus.magnifyingglass") }

            Menu("\(Int(editor.zoomScale * 100))%") {
                ForEach(zoomPresets, id: \.self) { preset in
                    Button("\(Int(preset * 100))%") { controller.setZoom(preset) }
                }
            }
            .frame(width: 64)

            Button {
                controller.setZoom(min(5.0, editor.zoomScale + 0.25))
            } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .softShadow()
    }
}
