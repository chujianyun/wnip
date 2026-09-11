import SwiftUI

enum OverlayToolbarAction: String, CaseIterable, Equatable, Sendable {
    case rectangle
    case ellipse
    case line
    case arrow
    case pen
    case mosaic
    case text
    case highlight
    case step
    case undo
    case cancel
    case copy
    case save
    case pin
    case background
}

struct AnnotationToolbar: View {
    static let preferredSize = CGSize(width: 556, height: 50)

    @ObservedObject var model: AnnotationCanvasModel
    let addingBackground: Bool
    let onAction: (OverlayToolbarAction) -> Void

    init(model: AnnotationCanvasModel? = nil, addingBackground: Bool = false, onAction: @escaping (OverlayToolbarAction) -> Void) {
        self.addingBackground = addingBackground
        self.model = model ?? AnnotationCanvasModel()
        self.onAction = onAction
    }

    var body: some View {
        HStack(spacing: 4) {
            toolButton(.rectangle, systemImage: "square")
            toolButton(.ellipse, systemImage: "circle")
            toolButton(.line, systemImage: "line.diagonal")
            toolButton(.arrow, systemImage: "arrow.up.right")
            toolButton(.pen, systemImage: "pencil.tip")
            toolButton(.mosaic, systemImage: "square.grid.3x3.fill")
            toolButton(.text, systemImage: "textformat")
            toolButton(.highlight, systemImage: "highlighter")
            toolButton(.step, systemImage: "1.circle.fill")

            Divider().frame(height: 22)

            toolButton(.undo, systemImage: "arrow.uturn.backward")
            toolButton(.cancel, systemImage: "xmark", tint: .red)
            if addingBackground {
                Button("添加背景 →") { onAction(.copy) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("下一步：添加背景")
                    .help("下一步：添加背景（Return）")
            } else {
                toolButton(.background, systemImage: "photo.badge.plus")
                toolButton(.pin, systemImage: "pin")
                toolButton(.copy, systemImage: "doc.on.doc")
                toolButton(.save, systemImage: "square.and.arrow.down")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { }
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }

    private func toolButton(
        _ action: OverlayToolbarAction,
        systemImage: String,
        tint: Color = .black.opacity(0.78)
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 31, height: 31)
                .background(
                    action.annotationTool == model.selectedTool ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
        .help(action.accessibilityLabel)
    }
}

private extension OverlayToolbarAction {
    var annotationTool: AnnotationTool? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .pen: .pen
        case .mosaic: .mosaic
        case .text: .text
        case .highlight: .highlight
        case .step: .step
        case .undo, .cancel, .copy, .save, .pin, .background: nil
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .pen: "Pen"
        case .mosaic: "Mosaic"
        case .text: "Text"
        case .highlight: "Highlight"
        case .step: "Step Number"
        case .undo: "Undo"
        case .cancel: "Cancel"
        case .copy: "Copy"
        case .save: "Save"
        case .background: "添加背景"
        case .pin: "Pin Screenshot (⌘⇧P)"
        }
    }
}
