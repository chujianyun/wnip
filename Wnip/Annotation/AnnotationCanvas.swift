import AppKit
import SwiftUI

struct AnnotationCanvasTransform: Equatable, Sendable {
    let sourceBounds: CGRect
    let visibleSourceRect: CGRect
    let canvasSize: CGSize

    init?(sourceBounds: CGRect, cropRect: CGRect?, canvasSize: CGSize) {
        let sourceBounds = sourceBounds.standardized
        guard !sourceBounds.isEmpty,
              canvasSize.width.isFinite,
              canvasSize.height.isFinite,
              canvasSize.width > 0,
              canvasSize.height > 0 else { return nil }
        let requested: CGRect
        if let cropRect {
            requested = cropRect.standardized.intersection(sourceBounds)
            guard !requested.isNull, !requested.isEmpty else { return nil }
        } else {
            requested = sourceBounds
        }
        self.sourceBounds = sourceBounds
        self.visibleSourceRect = requested
        self.canvasSize = canvasSize
    }

    var sourceImageFrameInCanvas: CGRect {
        CGRect(
            x: viewportOffset.x + ((sourceBounds.minX - visibleSourceRect.minX) * scale),
            y: viewportOffset.y + ((sourceBounds.minY - visibleSourceRect.minY) * scale),
            width: sourceBounds.width * scale,
            height: sourceBounds.height * scale
        )
    }

    var visibleCanvasRect: CGRect {
        CGRect(
            origin: viewportOffset,
            size: CGSize(
                width: visibleSourceRect.width * scale,
                height: visibleSourceRect.height * scale
            )
        )
    }

    func canvasPoint(forSourcePoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: viewportOffset.x + ((point.x - visibleSourceRect.minX) * scale),
            y: viewportOffset.y + ((point.y - visibleSourceRect.minY) * scale)
        )
    }

    func sourcePoint(forCanvasPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: visibleSourceRect.minX + ((point.x - viewportOffset.x) / scale),
            y: visibleSourceRect.minY + ((point.y - viewportOffset.y) / scale)
        )
    }

    func canvasRect(forSourceRect rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let origin = canvasPoint(forSourcePoint: rect.origin)
        return CGRect(
            origin: origin,
            size: CGSize(width: rect.width * scale, height: rect.height * scale)
        )
    }

    func canvasLength(forSourceLength length: CGFloat) -> CGFloat {
        length * scale
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
            ),
            resolvedArrowGeometry: annotation.arrowGeometry?.mapPoints(canvasPoint(forSourcePoint:))
        )
    }

    private var scale: CGFloat {
        min(
            canvasSize.width / max(1, visibleSourceRect.width),
            canvasSize.height / max(1, visibleSourceRect.height)
        )
    }

    private var viewportOffset: CGPoint {
        CGPoint(
            x: (canvasSize.width - (visibleSourceRect.width * scale)) / 2,
            y: (canvasSize.height - (visibleSourceRect.height * scale)) / 2
        )
    }
}

enum AnnotationCanvasInteractionMode: Equatable, Sendable {
    case drawing(AnnotationTool)
    case selecting
}

struct AnnotationCanvasRenderItem: Equatable, Sendable {
    let annotation: Annotation
    let isPreview: Bool
}

struct AnnotationCanvasTextLayout: Equatable, Sendable {
    let renderedFrame: CGRect
    let value: String
    let fontSize: CGFloat

    init?(annotation: Annotation) {
        guard case .text(_, let value) = annotation.content,
              let textGeometry = annotation.textGeometry else { return nil }
        self.renderedFrame = textGeometry.frame
        self.value = value
        self.fontSize = annotation.parameters.fontSize
    }
}

struct AnnotationTextEditorLayout: Equatable, Sendable {
    let frame: CGRect

    init(origin: CGPoint, value: String, fontSize: CGFloat, maxWidth: CGFloat) {
        let resolvedFontSize = fontSize.isFinite ? max(1, fontSize) : 1
        let measured = AnnotationTextGeometry(
            origin: .zero,
            value: value.isEmpty ? "M" : value,
            fontSize: resolvedFontSize
        ).frame
        let desiredWidth = max(resolvedFontSize * 2, measured.width + 12)
        let availableWidth = maxWidth.isFinite ? max(1, maxWidth) : 1
        frame = CGRect(
            origin: origin,
            size: CGSize(
                width: min(desiredWidth, availableWidth),
                height: max(resolvedFontSize * 1.4, measured.height + 6)
            )
        )
    }
}

@MainActor
enum AnnotationTextInput {
    static var activeEditorValue: String? {
        let keyWindow = NSApp.keyWindow
        let candidateWindows = [keyWindow].compactMap { $0 } + NSApp.windows.filter { $0 !== keyWindow }
        return candidateWindows.lazy.compactMap { window in
            guard let fieldEditor = window.firstResponder as? NSTextView,
                  fieldEditor.isFieldEditor else { return nil }
            return fieldEditor.string
        }.first
    }
}

struct AnnotationCanvasRenderSegment: Equatable, Sendable {
    let start: CGPoint
    let end: CGPoint
}

struct AnnotationCanvasArrowRenderLayout: Equatable, Sendable {
    let shaft: AnnotationCanvasRenderSegment
    let heads: [AnnotationCanvasRenderSegment]

    init?(annotation: Annotation) {
        guard case .arrow = annotation.content,
              let geometry = annotation.arrowGeometry else { return nil }
        shaft = AnnotationCanvasRenderSegment(start: geometry.start, end: geometry.tip)
        heads = [geometry.headA, geometry.headB].compactMap { head in
            guard head != geometry.tip else { return nil }
            return AnnotationCanvasRenderSegment(start: geometry.tip, end: head)
        }
    }
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
        if textEditorOrigin != nil, action != .cancel { _ = commitActiveTextInput() }
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
        case .undo, .cancel, .copy, .save, .pin, .background: return false
        }
        selectTool(tool)
        return true
    }

    func pointerDown(at point: CGPoint) {
        if textEditorOrigin != nil { _ = commitActiveTextInput() }
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

    @discardableResult
    func commitActiveTextInput() -> Bool {
        commitText(AnnotationTextInput.activeEditorValue ?? textDraft)
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
        var insertedPreview = false
        var items = document.annotations.map { annotation in
            if annotation.id == replacedID, let previewAnnotation {
                insertedPreview = true
                return AnnotationCanvasRenderItem(annotation: previewAnnotation, isPreview: true)
            }
            return AnnotationCanvasRenderItem(annotation: annotation, isPreview: false)
        }
        if let previewAnnotation, !insertedPreview {
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
    var viewport: CGRect? = nil
    var showsEditingControls = true
    var parameterControlsFrame: CGRect? = nil
    var displaysParameterControls = true
    @StateObject private var mosaicImageCache = AnnotationCanvasMosaicImageCache()

    @FocusState private var isTextFieldFocused: Bool
    @State private var cursorState = AnnotationCanvasCursorState()

    var body: some View {
        GeometryReader { proxy in
            if let transform = canvasTransform(canvasSize: proxy.size) {
                let pixelatedSource = model.renderItems.contains(where: { $0.annotation.tool == .mosaic })
                    ? sourceImage.flatMap { mosaicImageCache.image(for: $0) } : nil
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        if let sourceImage {
                            let imageFrame = transform.sourceImageFrameInCanvas
                            Image(nsImage: sourceImage)
                                .resizable()
                                .frame(width: imageFrame.width, height: imageFrame.height)
                                .position(x: imageFrame.midX, y: imageFrame.midY)
                        }

                        if let pixelatedSource {
                            mosaicOverlay(image: pixelatedSource, transform: transform, canvasSize: proxy.size)
                        }
                        Canvas { context, _ in
                            for item in model.renderItems {
                                if item.annotation.tool == .mosaic { continue }
                                draw(
                                    transform.canvasAnnotation(item.annotation),
                                    in: &context,
                                    isPreview: item.isPreview
                                )
                            }
                        }
                        .contentShape(AnnotationCanvasViewportShape(rect: viewport ?? transform.visibleCanvasRect))
                        .gesture(canvasDrag(transform: transform))
                        .onHover { inside in
                            cursorState.setPointerInside(inside, activeCursor: model.cursorKind)
                            cursorState.displayedCursor.nsCursor.set()
                        }
                        .onChange(of: model.cursorKind) { _, cursor in
                            cursorState.activeCursorChanged(cursor)
                            cursorState.displayedCursor.nsCursor.set()
                        }

                        if showsEditingControls, let selectedAnnotation = model.selectedAnnotation {
                            selectionHandles(for: transform.canvasAnnotation(selectedAnnotation).bounds)
                        }

                        if let origin = model.textEditorOrigin {
                            let canvasOrigin = transform.canvasPoint(forSourcePoint: origin)
                            let canvasFontSize = transform.canvasLength(
                                forSourceLength: model.parameters.fontSize
                            )
                            let editorLayout = AnnotationTextEditorLayout(
                                origin: canvasOrigin,
                                value: model.textDraft,
                                fontSize: canvasFontSize,
                                maxWidth: transform.visibleCanvasRect.maxX - canvasOrigin.x
                            )
                            TextField("Text", text: $model.textDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: canvasFontSize))
                                .foregroundStyle(model.parameters.color.swiftUIColor)
                                .padding(.horizontal, 4)
                                .frame(
                                    width: editorLayout.frame.width,
                                    height: editorLayout.frame.height,
                                    alignment: .leading
                                )
                                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                                .position(
                                    x: editorLayout.frame.midX,
                                    y: editorLayout.frame.midY
                                )
                                .focused($isTextFieldFocused)
                                .onSubmit { _ = model.commitActiveTextInput() }
                                .onExitCommand { model.cancelTextEditing() }
                        }
                    }
                    .clipShape(AnnotationCanvasViewportShape(rect: viewport ?? transform.visibleCanvasRect))

                    if showsEditingControls, displaysParameterControls {
                        let frame = parameterControlsFrame ?? AnnotationParameterControlsPlacement.resolveLocal(
                            selection: viewport ?? transform.visibleCanvasRect, canvasSize: proxy.size)
                        AnnotationParameterControls(model: model)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .onChange(of: model.textEditorOrigin) { _, origin in
                    isTextFieldFocused = origin != nil
                }
                .onDeleteCommand { _ = model.deleteSelection() }
            }
        }
    }

    func showsParameterControls(_ visible: Bool) -> Self {
        var copy = self
        copy.displaysParameterControls = visible
        return copy
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

    private func canvasTransform(canvasSize: CGSize) -> AnnotationCanvasTransform? {
        let sourceBounds: CGRect
        if let documentSourceBounds = model.document.sourceBounds {
            sourceBounds = documentSourceBounds
        } else if let sourceImage {
            sourceBounds = CGRect(origin: .zero, size: sourceImage.size)
        } else {
            sourceBounds = CGRect(origin: .zero, size: canvasSize)
        }
        return AnnotationCanvasTransform(
            sourceBounds: sourceBounds,
            cropRect: model.document.cropRect,
            canvasSize: canvasSize
        )
    }

    private func mosaicOverlay(
        image: NSImage,
        transform: AnnotationCanvasTransform,
        canvasSize: CGSize
    ) -> some View {
        let imageFrame = transform.sourceImageFrameInCanvas
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .mask {
            Canvas { context, _ in
                for item in model.renderItems {
                    let annotation = transform.canvasAnnotation(item.annotation)
                    guard case .mosaic(let points) = annotation.content else { continue }
                    context.stroke(
                        Path.polyline(points),
                        with: .color(.white),
                        style: StrokeStyle(
                            lineWidth: annotation.parameters.lineWidth,
                            lineCap: .square,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
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
        case .arrow:
            guard let layout = AnnotationCanvasArrowRenderLayout(annotation: annotation) else { return }
            context.stroke(Path.arrow(layout), with: .color(color), style: strokeStyle)
        case .pen(let points):
            context.stroke(Path.polyline(points), with: .color(color), style: strokeStyle)
        case .mosaic(let points):
            context.stroke(
                Path.polyline(points),
                with: .color(.black.opacity(isPreview ? 0.2 : 0.28)),
                style: StrokeStyle(lineWidth: annotation.parameters.lineWidth, lineCap: .square)
            )
        case .text(_, let value):
            guard let layout = AnnotationCanvasTextLayout(annotation: annotation) else { return }
            context.drawLayer { layer in
                layer.clip(to: Path(layout.renderedFrame))
                layer.draw(
                    Text(value).font(.system(size: layout.fontSize)).foregroundStyle(color),
                    at: layout.renderedFrame.origin,
                    anchor: .topLeading
                )
            }
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

struct AnnotationParameterControls: View {
    static let preferredSize = CGSize(width: 220, height: 36)

    @ObservedObject var model: AnnotationCanvasModel

    var body: some View {
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
        .frame(
            width: Self.preferredSize.width,
            height: Self.preferredSize.height,
            alignment: .leading
        )
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
}

@MainActor
private final class AnnotationCanvasMosaicImageCache: ObservableObject {
    private var sourceIdentifier: ObjectIdentifier?
    private var image: NSImage?

    func image(for source: NSImage) -> NSImage? {
        var proposedRect = CGRect(origin: .zero, size: source.size)
        guard let sourceImage = source.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else { return nil }

        let identifier = ObjectIdentifier(sourceImage)
        if identifier == sourceIdentifier {
            return image
        }

        let scale = source.size.width > 0
            ? CGFloat(sourceImage.width) / source.size.width
            : 1
        let colorSpace = sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        image = MosaicEffect.pixelatedImage(
            sourceImage,
            scale: scale,
            colorSpace: colorSpace
        ).map { pixelated in
            NSImage(cgImage: pixelated, size: source.size)
        }
        sourceIdentifier = identifier
        return image
    }
}

private struct AnnotationCanvasViewportShape: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        Path(rect)
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

    static func arrow(_ layout: AnnotationCanvasArrowRenderLayout) -> Path {
        var path = line(from: layout.shaft.start, to: layout.shaft.end)
        for head in layout.heads {
            path.move(to: head.start)
            path.addLine(to: head.end)
        }
        return path
    }
}
