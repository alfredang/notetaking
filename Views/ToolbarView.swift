import SwiftUI

/// GoodNotes-style horizontal tool bar across the top of the editor. Kept
/// compact so it fits without scrolling (color/size open as popovers; actions
/// on a selected element appear in the on-canvas edit menu).
struct ToolbarView: View {
    @Bindable var editor: EditorViewModel
    let controller: CanvasController

    @State private var showColorPopover = false
    @State private var showShapePopover = false
    @State private var showFlowchartPopover = false
    @State private var showTemplatePopover = false

    var body: some View {
        HStack(spacing: 8) {
            toolGroup
            if colorBinding != nil || sizeBinding != nil {
                Divider().frame(height: 28)
            }
            if let cb = colorBinding { colorButton(cb) }
            if let sb = sizeBinding { widthMenu(sizes: sb.sizes, selection: sb.value) }
            Spacer(minLength: 8)
            pageControls
            Divider().frame(height: 28)
            historyControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Tools

    private var toolGroup: some View {
        HStack(spacing: 4) {
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Self.toolName(tool))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private static func toolName(_ tool: EditorTool) -> String {
        switch tool {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraserPixel: "Eraser"
        case .eraserObject: "Object eraser"
        case .selection: "Lasso select"
        case .shape(.stickyNote): "Sticky note"
        case .shape: "Shape"
        case .flowchart: "Flowchart"
        }
    }

    private var shapeMenu: some View {
        Button {
            showShapePopover = true
        } label: {
            menuLabel("square.on.circle", active: isShapeActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shapes")
        .popover(isPresented: $showShapePopover) {
            ShapePalettePopover(
                title: "SHAPES",
                kinds: ShapeKind.plainShapes,
                selected: activeShapeKind(for: .shape)
            ) { kind in
                editor.tool = .shape(kind)
                showShapePopover = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var flowchartMenu: some View {
        Button {
            showFlowchartPopover = true
        } label: {
            menuLabel("flowchart", active: isFlowchartActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Flowchart")
        .popover(isPresented: $showFlowchartPopover) {
            ShapePalettePopover(
                title: "FLOWCHART",
                kinds: ShapeKind.flowchartShapes,
                selected: activeShapeKind(for: .flowchart)
            ) { kind in
                editor.tool = .flowchart(kind)
                showFlowchartPopover = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    /// The kind currently selected for a given overlay family (.shape / .flowchart).
    private enum ToolFamily { case shape, flowchart }
    private func activeShapeKind(for family: ToolFamily) -> ShapeKind? {
        switch (family, editor.tool) {
        case (.shape, .shape(let k)) where k != .stickyNote: return k
        case (.flowchart, .flowchart(let k)): return k
        default: return nil
        }
    }

    private func menuLabel(_ systemImage: String, active: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19))
            .frame(width: 38, height: 38)
            .background(active ? Color.accentColor.opacity(0.2) : .clear)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }

    private var isShapeActive: Bool {
        if case .shape(let kind) = editor.tool, kind != .stickyNote { return true }
        return false
    }
    private var isFlowchartActive: Bool {
        if case .flowchart = editor.tool { return true }
        return false
    }

    // MARK: - Color (popover) + size (menu) for the active tool

    private var colorBinding: Binding<RGBAColor>? {
        switch editor.tool {
        case .pen: return $editor.penColor
        case .highlighter: return $editor.highlighterColor
        case .shape, .flowchart: return $editor.shapeStrokeColor
        default: return nil
        }
    }

    private var sizeBinding: (sizes: [CGFloat], value: Binding<CGFloat>)? {
        switch editor.tool {
        case .pen: return (ToolDefaults.penSizes, $editor.penWidth)
        case .highlighter: return (ToolDefaults.highlighterSizes, $editor.highlighterWidth)
        case .eraserPixel: return ([10, 20, 30, 45, 60], $editor.eraserWidth)
        case .shape, .flowchart: return (ToolDefaults.shapeWidths, $editor.shapeLineWidth)
        default: return nil
        }
    }

    private func colorButton(_ selection: Binding<RGBAColor>) -> some View {
        Button {
            showColorPopover = true
        } label: {
            Circle()
                .fill(selection.wrappedValue.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Color")
        .popover(isPresented: $showColorPopover) {
            ColorPalettePopover(selection: selection)
                .presentationCompactAdaptation(.popover)
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
                    .frame(width: min(selection.wrappedValue + 2, 16),
                           height: min(selection.wrappedValue + 2, 16))
                    .frame(width: 20, height: 20)
                Text("\(Int(selection.wrappedValue))").font(.caption.monospacedDigit())
            }
            .frame(height: 34)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .hoverEffect(.highlight)
        .accessibilityLabel("Stroke width")
    }

    // MARK: - Page controls (template / add page / clear)

    private var pageControls: some View {
        HStack(spacing: 4) {
            Button {
                showTemplatePopover = true
            } label: {
                barIcon("square.grid.2x2")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Page template")
            .popover(isPresented: $showTemplatePopover) {
                TemplatePalettePopover(
                    current: controller.currentPaperStyle()
                ) { style in
                    controller.setPaperStyle(style)
                    showTemplatePopover = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Menu {
                Button { controller.requestNewPageAbove() } label: {
                    Label("Add Page Above", systemImage: "arrow.up.to.line")
                }
                Button { controller.requestNewPageBelow() } label: {
                    Label("Add Page Below", systemImage: "arrow.down.to.line")
                }
            } label: {
                barIcon("plus.rectangle.portrait")
            }
            .accessibilityLabel("Add page")

            Menu {
                Button(role: .destructive) {
                    controller.clearVisiblePage()
                    controller.refreshThumbnails()
                } label: { Label("Clear Page", systemImage: "trash.slash") }
                Button(role: .destructive) {
                    controller.clearAllPages()
                    controller.refreshThumbnails()
                } label: { Label("Clear All Pages", systemImage: "trash") }
                Divider()
                Button(role: .destructive) {
                    controller.deleteVisiblePage()
                } label: { Label("Delete Current Page", systemImage: "rectangle.portrait.badge.minus") }
            } label: {
                barIcon("trash")
            }
            .accessibilityLabel("Clear or delete page")
        }
    }

    private func barIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .frame(width: 38, height: 38)
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }

    // MARK: - History

    private var historyControls: some View {
        HStack(spacing: 4) {
            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Undo")
            .keyboardShortcut("z", modifiers: .command)
            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Redo")
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}

/// Swatch grid + system color picker shown in the color dropdown/popover.
private struct ColorPalettePopover: View {
    @Binding var selection: RGBAColor

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 10), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(ToolDefaults.extendedPalette.enumerated()), id: \.offset) { _, color in
                    Button {
                        selection = color
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.accentColor,
                                                     lineWidth: selection == color ? 3 : 0))
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            ColorPicker(selection: Binding(
                get: { selection.color },
                set: { selection = RGBAColor($0) }
            )) {
                Text("Custom color…").font(.subheadline)
            }
        }
        .padding(16)
        .frame(width: 268)
    }
}

/// A titled 4-column grid of shape previews (Shapes / Flowchart palettes).
private struct ShapePalettePopover: View {
    let title: String
    let kinds: [ShapeKind]
    let selected: ShapeKind?
    let onPick: (ShapeKind) -> Void

    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(kinds, id: \.self) { kind in
                    Button { onPick(kind) } label: {
                        ShapeGlyph(kind: kind)
                            .foregroundStyle(selected == kind ? Color.accentColor : Color.primary.opacity(0.7))
                            .frame(width: 40, height: 40)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected == kind ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel(kind.rawValue)
                }
            }
        }
        .padding(16)
        .frame(width: 4 * 56 + 2 * 10 + 32)
    }
}

/// A titled list of paper templates: swatch + name, with the active one highlighted.
private struct TemplatePalettePopover: View {
    let current: PaperStyle
    let onPick: (PaperStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEMPLATE")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            ForEach(PaperStyle.allCases) { style in
                Button { onPick(style) } label: {
                    HStack(spacing: 14) {
                        PaperSwatch(style: style)
                        Text(style.displayName)
                            .font(.body)
                            .foregroundStyle(current == style ? Color.accentColor : Color.primary)
                        Spacer(minLength: 8)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(current == style ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(current == style ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
