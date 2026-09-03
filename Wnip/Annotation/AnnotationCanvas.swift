import AppKit
import SwiftUI

@MainActor
final class AnnotationCanvasModel: ObservableObject {
    @Published private(set) var document: AnnotationDocument
    @Published private(set) var selectedTool: AnnotationTool
    @Published var parameters: AnnotationToolParameters
    @Published private(set) var selectedAnnotationID: UUID?
    @Published private(set) var previewAnnotation: Annotation?
    @Published private(set) var textEditorOrigin: CGPoint?
    @Published var textDraft = ""

    private enum Interaction {
        case drawing(start: CGPoint, points: [CGPoint])
        case moving(id: UUID, start: CGPoint, original: Annotation)
    }

    private var interaction: Interaction?

    init(document: AnnotationDocument = AnnotationDocument(), selectedTool: AnnotationTool = .rectangle) {
        self.document = document
        self.selectedTool = selectedTool
        self.parameters = selectedTool.defaultParameters
    }

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        parameters = tool.defaultParameters
        selectedAnnotationID = nil
        previewAnnotation = nil
        interaction = nil
    }

    @discardableResult
    func handleToolbarAction(_ action: OverlayToolbarAction) -> Bool {
        let tool: AnnotationTool
        switch action {
        case .rectangle: tool = .rectangle
        case .ellipse: tool = .ellipse
        case .line: tool = .line
        case .arrow: tool = .arrow
        case .pen: tool = .pen
        case .mosaic: tool = .mosaic
        case .text: tool = .text
        case .highlight: tool = .highlight
        case .step: tool = .step
        case .undo, .cancel, .copy, .save: return false
        }
        selectTool(tool)
        return true
    }

    func pointerDown(at point: CGPoint) {
        if let annotation = document.hitTest(point) {
            selectedAnnotationID = annotation.id
            interaction = .moving(id: annotation.id, start: point, original: annotation)
            previewAnnotation = annotation
            return
        }

        selectedAnnotationID = nil
        interaction = .drawing(start: point, points: [point])
        previewAnnotation = makeAnnotation(start: point, end: point, points: [point])
    }

    func pointerDragged(to point: CGPoint) {
        guard let interaction else { return }
        switch interaction {
        case .moving(let id, let start, let original):
            selectedAnnotationID = id
            previewAnnotation = original.translated(
                by: CGSize(width: point.x - start.x, height: point.y - start.y)
            )
        case .drawing(let start, var points):
            if selectedTool.usesFreehandPoints, points.last != point {
                points.append(point)
            }
            self.interaction = .drawing(start: start, points: points)
            previewAnnotation = makeAnnotation(start: start, end: point, points: points)
        }
    }

    func pointerUp(at point: CGPoint) {
        guard let interaction else { return }
        defer {
            self.interaction = nil
            previewAnnotation = nil
        }

        switch interaction {
        case .moving(let id, let start, _):
            let offset = CGSize(width: point.x - start.x, height: point.y - start.y)
            _ = document.perform(.move(id: id, offset: offset))
        case .drawing(let start, var points):
            if selectedTool == .text {
                textEditorOrigin = start
                textDraft = ""
                return
            }
            if selectedTool.usesFreehandPoints, points.last != point {
                points.append(point)
            }
            guard let annotation = makeAnnotation(start: start, end: point, points: points) else { return }
            if document.perform(.add(annotation)) {
                selectedAnnotationID = annotation.id
            }
        }
    }

    @discardableResult
    func commitText(_ value: String? = nil) -> Bool {
        guard let origin = textEditorOrigin else { return false }
        let text = (value ?? textDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        textEditorOrigin = nil
        textDraft = ""
        guard !text.isEmpty else { return false }
        let annotation = Annotation(
            content: .text(origin: origin, value: text),
            parameters: parameters
        )
        let committed = document.perform(.add(annotation))
        if committed {
            selectedAnnotationID = annotation.id
        }
        return committed
    }

    func cancelTextEditing() {
        textEditorOrigin = nil
        textDraft = ""
    }

    @discardableResult
    func deleteSelection() -> Bool {
        guard let selectedAnnotationID else { return false }
        let deleted = document.perform(.delete(id: selectedAnnotationID))
        if deleted {
            self.selectedAnnotationID = nil
        }
        return deleted
    }

    @discardableResult
    func crop(to rect: CGRect) -> Bool {
        document.perform(.crop(rect))
    }

    @discardableResult
    func undo() -> Bool {
        let undone = document.undo()
        if let selectedAnnotationID,
           !document.annotations.contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = nil
        }
        return undone
    }

    var selectedAnnotation: Annotation? {
        document.annotations.first { $0.id == selectedAnnotationID }
    }

    private func makeAnnotation(
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint]
    ) -> Annotation? {
        let content: AnnotationContent
        switch selectedTool {
        case .rectangle:
            content = .rectangle(CGRect.spanning(start, end))
        case .ellipse:
            content = .ellipse(CGRect.spanning(start, end))
        case .line:
            content = .line(from: start, to: end)
        case .arrow:
            content = .arrow(from: start, to: end)
        case .pen:
            content = .pen(points)
        case .mosaic:
            content = .mosaic(points)
        case .text:
            return nil
        case .highlight:
            content = .highlight(points)
        case .step:
            content = .step(center: end, number: document.nextStepNumber)
        }
        return Annotation(content: content, parameters: parameters)
    }
}

struct AnnotationCanvas: View {
    @ObservedObject var model: AnnotationCanvasModel
    var sourceImage: NSImage?

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let sourceImage {
                    Image(nsImage: sourceImage)
                        .resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                Canvas { context, _ in
                    for annotation in model.document.annotations {
                        draw(annotation, in: &context, isPreview: false)
                    }
                    if let preview = model.previewAnnotation {
                        draw(preview, in: &context, isPreview: true)
                    }
                }
                .contentShape(Rectangle())
                .gesture(canvasDrag)
                .onHover { inside in
                    (inside ? cursor(for: model.selectedTool) : NSCursor.arrow).set()
                }

                if let bounds = model.selectedAnnotation?.bounds {
                    selectionHandles(for: bounds)
                }

                if let origin = model.textEditorOrigin {
                    TextField("Text", text: $model.textDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: model.parameters.fontSize))
                        .foregroundStyle(model.parameters.color.swiftUIColor)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 120, minHeight: model.parameters.fontSize * 1.4)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                        .position(
                            x: origin.x + 60,
                            y: origin.y + model.parameters.fontSize * 0.7
                        )
                        .focused($isTextFieldFocused)
                        .onSubmit { _ = model.commitText() }
                        .onExitCommand { model.cancelTextEditing() }
                }

                parameterControls
                    .padding(8)
            }
            .clipped()
            .onChange(of: model.textEditorOrigin) { _, origin in
                isTextFieldFocused = origin != nil
            }
            .onDeleteCommand { _ = model.deleteSelection() }
        }
    }

    private var canvasDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if value.translation == .zero {
                    model.pointerDown(at: value.startLocation)
                }
                model.pointerDragged(to: value.location)
            }
            .onEnded { value in
                model.pointerUp(at: value.location)
            }
    }

    private var parameterControls: some View {
        HStack(spacing: 8) {
            ColorPicker("Color", selection: colorBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .disabled(model.selectedTool == .mosaic)

            Image(systemName: "lineweight")
            Slider(value: lineWidthBinding, in: 1...32, step: 1)
                .frame(width: 90)

            if model.selectedTool == .text || model.selectedTool == .step {
                Stepper("\(Int(model.parameters.fontSize)) pt", value: fontSizeBinding, in: 10...72, step: 1)
                    .frame(width: 108)
            }

            if model.selectedAnnotationID != nil {
                Button(role: .destructive) {
                    _ = model.deleteSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete Annotation")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { model.parameters.color.swiftUIColor },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                model.parameters.color = AnnotationColor(
                    red: converted.redComponent,
                    green: converted.greenComponent,
                    blue: converted.blueComponent,
                    alpha: converted.alphaComponent
                )
            }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { Double(model.parameters.lineWidth) },
            set: { model.parameters.lineWidth = CGFloat($0) }
        )
    }

    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { Int(model.parameters.fontSize) },
            set: { model.parameters.fontSize = CGFloat($0) }
        )
    }

    private func selectionHandles(for rect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: max(1, rect.width), height: max(1, rect.height))
                .position(x: rect.midX, y: rect.midY)

            ForEach(Array(handleCenters(for: rect).enumerated()), id: \.offset) { _, center in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleCenters(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY)
        ]
    }

    private func cursor(for tool: AnnotationTool) -> NSCursor {
        tool == .text ? .iBeam : .crosshair
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, isPreview: Bool) {
        let opacity = isPreview ? 0.68 : 1
        let color = annotation.parameters.color.swiftUIColor.opacity(opacity)
        let strokeStyle = StrokeStyle(
            lineWidth: annotation.parameters.lineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        switch annotation.content {
        case .rectangle(let rect):
            context.stroke(Path(rect.standardized), with: .color(color), style: strokeStyle)
        case .ellipse(let rect):
            context.stroke(Path(ellipseIn: rect.standardized), with: .color(color), style: strokeStyle)
        case .line(let start, let end):
            context.stroke(Path.line(from: start, to: end), with: .color(color), style: strokeStyle)
        case .arrow(let start, let end):
            context.stroke(Path.arrow(from: start, to: end), with: .color(color), style: strokeStyle)
        case .pen(let points):
            context.stroke(Path.polyline(points), with: .color(color), style: strokeStyle)
        case .mosaic(let points):
            context.stroke(
                Path.polyline(points),
                with: .color(.black.opacity(isPreview ? 0.2 : 0.28)),
                style: StrokeStyle(lineWidth: annotation.parameters.lineWidth, lineCap: .square)
            )
        case .text(let origin, let value):
            context.draw(
                Text(value).font(.system(size: annotation.parameters.fontSize)).foregroundStyle(color),
                at: origin,
                anchor: .topLeading
            )
        case .highlight(let points):
            context.stroke(Path.polyline(points), with: .color(color), style: strokeStyle)
        case .step(let center, let number):
            let radius = max(annotation.parameters.fontSize * 0.75, 12)
            let circle = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(circle, with: .color(color))
            context.draw(
                Text(String(number))
                    .font(.system(size: annotation.parameters.fontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(opacity)),
                at: center,
                anchor: .center
            )
        }
    }
}

private extension AnnotationTool {
    var usesFreehandPoints: Bool {
        self == .pen || self == .mosaic || self == .highlight
    }
}

private extension CGRect {
    static func spanning(_ first: CGPoint, _ second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}

private extension AnnotationColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private extension Path {
    static func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    static func arrow(from start: CGPoint, to end: CGPoint) -> Path {
        var path = line(from: start, to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 12
        let spread: CGFloat = .pi / 6
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        ))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        ))
        return path
    }
}
