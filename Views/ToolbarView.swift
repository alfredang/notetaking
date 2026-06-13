import SwiftUI

/// GoodNotes-style horizontal tool bar that sits across the top of the editor.
struct ToolbarView: View {
    @Bindable var editor: EditorViewModel
    let controller: CanvasController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                toolGroup
                Divider().frame(height: 28)
                contextControls
                Divider().frame(height: 28)
                historyControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Tools

    private var toolGroup: some View {
        HStack(spacing: 6) {
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
                .font(.system(size: 19))
                .frame(width: 38, height: 38)
                .background(isActive ? Color.accentColor.opacity(0.2) : .clear)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
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
            .font(.system(size: 19))
            .frame(width: 38, height: 38)
            .background(active ? Color.accentColor.opacity(0.2) : .clear)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var isShapeActive: Bool {
        if case .shape(let kind) = editor.tool, kind != .stickyNote { return true }
        return false
    }
    private var isFlowchartActive: Bool {
        if case .flowchart = editor.tool { return true }; return false
    }

    // MARK: - Context controls (color + size for the active tool)

    @ViewBuilder
    private var contextControls: some View {
        switch editor.tool {
        case .pen:
            colorSwatches(selection: $editor.penColor)
            widthMenu(sizes: ToolDefaults.penSizes, selection: $editor.penWidth)
        case .highlighter:
            colorSwatches(selection: $editor.highlighterColor)
            widthMenu(sizes: ToolDefaults.highlighterSizes, selection: $editor.highlighterWidth)
        case .eraserPixel:
            widthMenu(sizes: [10, 20, 30, 45, 60], selection: $editor.eraserWidth)
        case .shape, .flowchart:
            colorSwatches(selection: $editor.shapeStrokeColor)
            widthMenu(sizes: ToolDefaults.shapeWidths, selection: $editor.shapeLineWidth)
            fillToggle
            selectionActions
        case .selection:
            recolorSwatches
            selectionActions
        default:
            EmptyView()
        }
    }

    /// Swatches that recolor the currently lasso-selected shape/flowchart item.
    private var recolorSwatches: some View {
        HStack(spacing: 8) {
            ForEach(Array(ToolDefaults.palette.enumerated()), id: \.offset) { _, color in
                Button {
                    controller.setSelectedColor(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func colorSwatches(selection: Binding<RGBAColor>) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(ToolDefaults.palette.enumerated()), id: \.offset) { _, color in
                Button {
                    selection.wrappedValue = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.accentColor,
                                                 lineWidth: selection.wrappedValue == color ? 3 : 0))
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: Binding(
                get: { selection.wrappedValue.color },
                set: { selection.wrappedValue = RGBAColor($0) }
            ))
            .labelsHidden()
            .frame(width: 28, height: 28)
        }
    }

    private func widthMenu(sizes: [CGFloat], selection: Binding<CGFloat>) -> some View {
        Menu {
            ForEach(sizes, id: \.self) { size in
                Button {
                    selection.wrappedValue = size
                } label: {
                    if selection.wrappedValue == size {
                        Label("\(Int(size)) px", systemImage: "checkmark")
                    } else {
                        Text("\(Int(size)) px")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.primary)
                    .frame(width: min(selection.wrappedValue + 2, 18),
                           height: min(selection.wrappedValue + 2, 18))
                    .frame(width: 22, height: 22)
                Text("\(Int(selection.wrappedValue))")
                    .font(.caption.monospacedDigit())
            }
            .frame(height: 34)
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var fillToggle: some View {
        Button {
            editor.shapeFillColor = editor.shapeFillColor.alpha > 0 ? .clear : editor.shapeStrokeColor
        } label: {
            Image(systemName: editor.shapeFillColor.alpha > 0 ? "square.fill" : "square")
                .font(.system(size: 18))
                .frame(width: 36, height: 34)
        }
        .buttonStyle(.plain)
    }

    private var selectionActions: some View {
        HStack(spacing: 6) {
            Button {
                controller.duplicateSelection()
            } label: { Image(systemName: "plus.square.on.square").frame(width: 36, height: 34) }
                .buttonStyle(.plain)
            Button(role: .destructive) {
                controller.deleteSelection()
            } label: { Image(systemName: "trash").frame(width: 36, height: 34) }
                .buttonStyle(.plain)
        }
    }

    // MARK: - History

    private var historyControls: some View {
        HStack(spacing: 6) {
            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
        }
    }
}
