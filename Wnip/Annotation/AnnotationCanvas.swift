import AppKit
import SwiftUI

struct AnnotationCanvasTransform: Equatable, Sendable {
    let sourceBounds: CGRect
    let visibleSourceRect: CGRect
    let canvasSize: CGSize

    init(sourceBounds: CGRect, cropRect: CGRect?, canvasSize: CGSize) {
        let sourceBounds = sourceBounds.standardized
        let requested = cropRect?.standardized.intersection(sourceBounds) ?? sourceBounds
        self.sourceBounds = sourceBounds
        self.visibleSourceRect = requested.isNull || requested.isEmpty ? sourceBounds : requested
        self.canvasSize = CGSize(width: max(1, canvasSize.width), height: max(1, canvasSize.height))
    }

    var sourceImageFrameInCanvas: CGRect {
        CGRect(
            x: -visibleSourceRect.minX * scaleX,
            y: -visibleSourceRect.minY * scaleY,
            width: sourceBounds.width * scaleX,
            height: sourceBounds.height * scaleY
        )
    }

    func canvasPoint(forSourcePoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - visibleSourceRect.minX) * scaleX,
            y: (point.y - visibleSourceRect.minY) * scaleY
        )
    }

    func sourcePoint(forCanvasPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: visibleSourceRect.minX + (point.x / scaleX),
            y: visibleSourceRect.minY + (point.y / scaleY)
        )
    }

    func canvasRect(forSourceRect rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let origin = canvasPoint(forSourcePoint: rect.origin)
        return CGRect(
            origin: origin,
            size: CGSize(width: rect.width * scaleX, height: rect.height * scaleY)
        )
    }

    func canvasLength(forSourceLength length: CGFloat) -> CGFloat {
        length * ((scaleX + scaleY) / 2)
    }

    func canvasAnnotation(_ annotation: Annotation) -> Annotation {
        let content: AnnotationContent
        switch annotation.content {
        case .rectangle(let rect):
            content = .rectangle(canvasRect(forSourceRect: rect))
        case .ellipse(let rect):
            content = .ellipse(canvasRect(forSourceRect: rect))
        case .line(let start, let end):
            content = .line(
                from: canvasPoint(forSourcePoint: start),
                to: canvasPoint(forSourcePoint: end)
            )
        case .arrow(let start, let end):
            content = .arrow(
                from: canvasPoint(forSourcePoint: start),
                to: canvasPoint(forSourcePoint: end)
            )
        case .pen(let points):
            content = .pen(points.map(canvasPoint(forSourcePoint:)))
        case .mosaic(let points):
            content = .mosaic(points.map(canvasPoint(forSourcePoint:)))
        case .text(let origin, let value):
            content = .text(origin: canvasPoint(forSourcePoint: origin), value: value)
        case .highlight(let points):
            content = .highlight(points.map(canvasPoint(forSourcePoint:)))
        case .step(let center, let number):
            content = .step(center: canvasPoint(forSourcePoint: center), number: number)
        }
        return Annotation(
            id: annotation.id,
            content: content,
            parameters: AnnotationToolParameters(
                color: annotation.parameters.color,
                lineWidth: canvasLength(forSourceLength: annotation.parameters.lineWidth),
                fontSize: canvasLength(forSourceLength: annotation.parameters.fontSize)
            )
        )
    }

    private var scaleX: CGFloat { canvasSize.width / max(1, visibleSourceRect.width) }
    private var scaleY: CGFloat { canvasSize.height / max(1, visibleSourceRect.height) }
}

enum AnnotationCanvasInteractionMode: Equatable, Sendable {
    case drawing(AnnotationTool)
    case selecting
}

struct AnnotationCanvasRenderItem: Equatable, Sendable {
    let annotation: Annotation
    let isPreview: Bool
}

enum AnnotationCanvasCursorKind: Equatable, Sendable {
    case arrow
    case crosshair
    case iBeam
    case openHand
    case closedHand
}

struct AnnotationCanvasCursorState: Equatable, Sendable {
    private(set) var isPointerInside = false
    private(set) var displayedCursor: AnnotationCanvasCursorKind = .arrow

    mutating func setPointerInside(
        _ isInside: Bool,
        activeCursor: AnnotationCanvasCursorKind
    ) {
        isPointerInside = isInside
        displayedCursor = isInside ? activeCursor : .arrow
    }

    mutating func activeCursorChanged(_ activeCursor: AnnotationCanvasCursorKind) {
        if isPointerInside {
            displayedCursor = activeCursor
        }
    }
}

@MainActor
final class AnnotationCanvasModel: ObservableObject {
    @Published private(set) var document: AnnotationDocument
    @Published private(set) var selectedTool: AnnotationTool
    @Published private(set) var interactionMode: AnnotationCanvasInteractionMode
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
    private var gestureIsActive = false

    init(document: AnnotationDocument = AnnotationDocument(), selectedTool: AnnotationTool = .rectangle) {
        self.document = document
        self.selectedTool = selectedTool
        self.interactionMode = .drawing(selectedTool)
        self.parameters = selectedTool.defaultParameters
    }

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        interactionMode = .drawing(tool)
        parameters = tool.defaultParameters
        selectedAnnotationID = nil
        previewAnnotation = nil
        interaction = nil
        gestureIsActive = false
    }

    func selectForMoving() {
        interactionMode = .selecting
        previewAnnotation = nil
        interaction = nil
        gestureIsActive = false
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
        if interactionMode == .selecting,
           let annotation = document.hitTest(point) {
            selectedAnnotationID = annotation.id
            interaction = .moving(id: annotation.id, start: point, original: annotation)
            previewAnnotation = annotation
            return
        }

        if interactionMode == .selecting {
            selectedAnnotationID = nil
            interaction = nil
            previewAnnotation = nil
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

    func gestureChanged(startLocation: CGPoint, location: CGPoint) {
        if !gestureIsActive {
            gestureIsActive = true
            pointerDown(at: startLocation)
        }
        pointerDragged(to: location)
    }

    func gestureEnded(startLocation: CGPoint, location: CGPoint) {
        if !gestureIsActive {
            pointerDown(at: startLocation)
        }
        pointerUp(at: location)
        gestureIsActive = false
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
        if previewAnnotation?.id == selectedAnnotationID {
            return previewAnnotation
        }
        return document.annotations.first { $0.id == selectedAnnotationID }
    }

    var renderItems: [AnnotationCanvasRenderItem] {
        let replacedID: UUID?
        if case .moving(let id, _, _) = interaction {
            replacedID = id
        } else {
            replacedID = nil
        }
        var items = document.annotations.compactMap { annotation in
            annotation.id == replacedID
                ? nil
                : AnnotationCanvasRenderItem(annotation: annotation, isPreview: false)
        }
        if let previewAnnotation {
            items.append(AnnotationCanvasRenderItem(annotation: previewAnnotation, isPreview: true))
        }
        return items
    }

    var cursorKind: AnnotationCanvasCursorKind {
        switch interactionMode {
        case .drawing(.text):
            return .iBeam
        case .drawing:
            return .crosshair
        case .selecting:
            if case .moving = interaction {
                return .closedHand
            }
            return .openHand
        }
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
    @State private var cursorState = AnnotationCanvasCursorState()

    var body: some View {
        GeometryReader { proxy in
            let transform = canvasTransform(canvasSize: proxy.size)
            ZStack(alignment: .topLeading) {
                if let sourceImage {
                    let imageFrame = transform.sourceImageFrameInCanvas
                    Image(nsImage: sourceImage)
                        .resizable()
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                }

                Canvas { context, _ in
                    for item in model.renderItems {
                        draw(
                            transform.canvasAnnotation(item.annotation),
                            in: &context,
                            isPreview: item.isPreview
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(canvasDrag(transform: transform))
                .onHover { inside in
                    cursorState.setPointerInside(inside, activeCursor: model.cursorKind)
                    cursorState.displayedCursor.nsCursor.set()
                }
                .onChange(of: model.cursorKind) { _, cursor in
                    cursorState.activeCursorChanged(cursor)
                    cursorState.displayedCursor.nsCursor.set()
                }

                if let selectedAnnotation = model.selectedAnnotation {
                    selectionHandles(for: transform.canvasAnnotation(selectedAnnotation).bounds)
                }

                if let origin = model.textEditorOrigin {
                    let canvasOrigin = transform.canvasPoint(forSourcePoint: origin)
                    let canvasFontSize = transform.canvasLength(
                        forSourceLength: model.parameters.fontSize
                    )
                    TextField("Text", text: $model.textDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: canvasFontSize))
                        .foregroundStyle(model.parameters.color.swiftUIColor)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 120, minHeight: canvasFontSize * 1.4)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                        .position(
                            x: canvasOrigin.x + 60,
                            y: canvasOrigin.y + canvasFontSize * 0.7
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

    private func canvasDrag(transform: AnnotationCanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                model.gestureChanged(
                    startLocation: transform.sourcePoint(forCanvasPoint: value.startLocation),
                    location: transform.sourcePoint(forCanvasPoint: value.location)
                )
            }
            .onEnded { value in
                model.gestureEnded(
                    startLocation: transform.sourcePoint(forCanvasPoint: value.startLocation),
                    location: transform.sourcePoint(forCanvasPoint: value.location)
                )
            }
    }

    private func canvasTransform(canvasSize: CGSize) -> AnnotationCanvasTransform {
        let sourceBounds: CGRect
        if let sourceImage {
            sourceBounds = CGRect(origin: .zero, size: sourceImage.size)
        } else if let cropRect = model.document.cropRect {
            sourceBounds = cropRect
        } else {
            sourceBounds = CGRect(origin: .zero, size: canvasSize)
        }
        return AnnotationCanvasTransform(
            sourceBounds: sourceBounds,
            cropRect: model.document.cropRect,
            canvasSize: canvasSize
        )
    }

    private var parameterControls: some View {
        HStack(spacing: 8) {
            Button {
                model.selectForMoving()
            } label: {
                Image(systemName: "cursorarrow")
                    .foregroundStyle(model.interactionMode == .selecting ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
            .help("Select and Move")

            ColorPicker("Color", selection: colorBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .disabled(model.selectedTool == .mosaic)

            if model.selectedTool.usesLineWidth {
                Image(systemName: "lineweight")
                Slider(value: lineWidthBinding, in: 1...32, step: 1)
                    .frame(width: 90)
            }

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
            let geometry = AnnotationArrowGeometry(
                start: start,
                tip: end,
                lineWidth: annotation.parameters.lineWidth
            )
            context.stroke(Path.arrow(geometry), with: .color(color), style: strokeStyle)
        case .pen(let points):
            context.stroke(Path.polyline(points), with: .color(color), style: strokeStyle)
        case .mosaic(let points):
            context.stroke(
                Path.polyline(points),
                with: .color(.black.opacity(isPreview ? 0.2 : 0.28)),
                style: StrokeStyle(lineWidth: annotation.parameters.lineWidth, lineCap: .square)
            )
        case .text(let origin, let value):
            let textOrigin = annotation.textGeometry?.frame.origin ?? origin
            context.draw(
                Text(value).font(.system(size: annotation.parameters.fontSize)).foregroundStyle(color),
                at: textOrigin,
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

private extension AnnotationCanvasCursorKind {
    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .crosshair: .crosshair
        case .iBeam: .iBeam
        case .openHand: .openHand
        case .closedHand: .closedHand
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

    static func arrow(_ geometry: AnnotationArrowGeometry) -> Path {
        var path = line(from: geometry.start, to: geometry.tip)
        path.move(to: geometry.tip)
        path.addLine(to: geometry.headA)
        path.move(to: geometry.tip)
        path.addLine(to: geometry.headB)
        return path
    }
}
