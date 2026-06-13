import SwiftUI

/// Floating tool palette for the editor.
struct ToolbarView: View {
    @Bindable var editor: EditorViewModel
    let controller: CanvasController

    @State private var showingCustomColor = false

    var body: some View {
        VStack(spacing: 14) {
            toolButtons
            Divider().frame(width: 36)
            contextControls
            Divider().frame(width: 36)
            historyControls
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.toolbarCornerRadius)
                .fill(.regularMaterial)
        )
        .softShadow()
    }

    // MARK: - Tool selection

    private var toolButtons: some View {
        VStack(spacing: 10) {
            toolButton("pencil.tip", tool: .pen, isActive: editor.tool == .pen)
            toolButton("highlighter", tool: .highlighter, isActive: editor.tool == .highlighter)
            toolButton("eraser", tool: .eraserPixel, isActive: editor.tool == .eraserPixel)
            toolButton("eraser.line.dashed", tool: .eraserObject, isActive: editor.tool == .eraserObject)
            toolButton("lasso", tool: .selection, isActive: editor.tool == .selection)
            shapeMenu
            flowchartMenu
            toolButton("note.text", tool: .shape(.stickyNote), isActive: editor.tool == .shape(.stickyNote))
        }
    }

    private func toolButton(_ systemImage: String, tool: EditorTool, isActive: Bool) -> some View {
        Button {
            editor.tool = tool
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(isActive ? Color.accentColor.opacity(0.2) : .clear)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var shapeMenu: some View {
        Menu {
            shapeItem("Rectangle", .rectangle)
            shapeItem("Circle", .circle)
            shapeItem("Triangle", .triangle)
            shapeItem("Diamond", .diamond)
            shapeItem("Line", .line)
            shapeItem("Arrow", .arrow)
        } label: {
            menuLabel("square.on.circle", active: isShapeActive)
        }
    }

    private var flowchartMenu: some View {
        Menu {
            shapeItem("Process", .process)
            shapeItem("Decision", .decision)
            shapeItem("Start / End", .startEnd)
            shapeItem("Connector", .connector)
        } label: {
            menuLabel("flowchart", active: isFlowchartActive)
        }
    }

    private func shapeItem(_ title: String, _ kind: ShapeKind) -> some View {
        Button(title) {
            editor.tool = kind.isNode || kind == .connector ? .flowchart(kind) : .shape(kind)
        }
    }

    private func menuLabel(_ systemImage: String, active: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20))
            .frame(width: 40, height: 40)
            .background(active ? Color.accentColor.opacity(0.2) : .clear)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var isShapeActive: Bool {
        if case .shape = editor.tool { return true }; return false
    }
    private var isFlowchartActive: Bool {
        if case .flowchart = editor.tool { return true }; return false
    }

    // MARK: - Context controls (size + color)

    @ViewBuilder
    private var contextControls: some View {
        switch editor.tool {
        case .pen:
            colorPalette(selection: $editor.penColor)
            sizePicker(sizes: ToolDefaults.penSizes, selection: $editor.penWidth)
        case .highlighter:
            colorPalette(selection: $editor.highlighterColor)
            sizePicker(sizes: ToolDefaults.highlighterSizes, selection: $editor.highlighterWidth)
        case .eraserPixel:
            sizeSlider(value: $editor.eraserWidth, range: 5...60, label: "Eraser")
        case .shape, .flowchart:
            colorPalette(selection: $editor.shapeStrokeColor)
            sizePicker(sizes: ToolDefaults.shapeWidths, selection: $editor.shapeLineWidth)
            fillToggle
            opacitySlider
            selectionActions
        case .selection:
            selectionActions
        default:
            EmptyView()
        }
    }

    private func colorPalette(selection: Binding<RGBAColor>) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(ToolDefaults.palette.enumerated()), id: \.offset) { _, color in
                Button {
                    selection.wrappedValue = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.accentColor, lineWidth: selection.wrappedValue == color ? 2.5 : 0)
                        )
                        .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: Binding(
                get: { selection.wrappedValue.color },
                set: { selection.wrappedValue = RGBAColor($0) }
            ))
            .labelsHidden()
            .frame(width: 26, height: 26)
        }
    }

    private func sizePicker(sizes: [CGFloat], selection: Binding<CGFloat>) -> some View {
        VStack(spacing: 6) {
            ForEach(sizes, id: \.self) { size in
                Button {
                    selection.wrappedValue = size
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: min(size + 4, 22), height: min(size + 4, 22))
                        .frame(width: 28, height: 28)
                        .background(selection.wrappedValue == size ? Color.accentColor.opacity(0.2) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sizeSlider(value: Binding<CGFloat>, range: ClosedRange<CGFloat>, label: String) -> some View {
        VStack {
            Text(label).font(.caption2)
            Slider(value: value, in: range)
                .frame(width: 44)
                .rotationEffect(.degrees(-90))
                .frame(height: 80)
        }
    }

    private var fillToggle: some View {
        Button {
            editor.shapeFillColor = editor.shapeFillColor.alpha > 0 ? .clear : editor.shapeStrokeColor
        } label: {
            Image(systemName: editor.shapeFillColor.alpha > 0 ? "square.fill" : "square")
                .font(.system(size: 18))
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var opacitySlider: some View {
        VStack {
            Image(systemName: "circle.lefthalf.filled").font(.caption2)
            Slider(value: $editor.shapeOpacity, in: 0.1...1)
                .frame(width: 44)
                .rotationEffect(.degrees(-90))
                .frame(height: 70)
        }
    }

    private var selectionActions: some View {
        VStack(spacing: 8) {
            Button {
                controller.duplicateSelection()
            } label: { Image(systemName: "plus.square.on.square").frame(width: 36, height: 32) }
                .buttonStyle(.plain)
            Button(role: .destructive) {
                controller.deleteSelection()
            } label: { Image(systemName: "trash").frame(width: 36, height: 32) }
                .buttonStyle(.plain)
        }
    }

    // MARK: - History

    private var historyControls: some View {
        VStack(spacing: 10) {
            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)
            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}
