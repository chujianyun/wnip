import CoreGraphics
import Foundation

struct AnnotationColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let red = AnnotationColor(red: 0.95, green: 0.16, blue: 0.22, alpha: 1)
    static let clear = AnnotationColor(red: 0, green: 0, blue: 0, alpha: 0)
    static let yellowHighlight = AnnotationColor(red: 1, green: 0.84, blue: 0, alpha: 0.38)
}

struct AnnotationToolParameters: Equatable, Sendable {
    var color: AnnotationColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    init(color: AnnotationColor, lineWidth: CGFloat, fontSize: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
    }
}

enum AnnotationTool: String, CaseIterable, Equatable, Sendable {
    case rectangle
    case ellipse
    case line
    case arrow
    case pen
    case mosaic
    case text
    case highlight
    case step

    var defaultParameters: AnnotationToolParameters {
        switch self {
        case .mosaic:
            AnnotationToolParameters(color: .clear, lineWidth: 18, fontSize: 18)
        case .highlight:
            AnnotationToolParameters(color: .yellowHighlight, lineWidth: 16, fontSize: 18)
        default:
            AnnotationToolParameters(color: .red, lineWidth: 3, fontSize: 18)
        }
    }
}

enum AnnotationContent: Equatable, Sendable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case line(from: CGPoint, to: CGPoint)
    case arrow(from: CGPoint, to: CGPoint)
    case pen([CGPoint])
    case mosaic([CGPoint])
    case text(origin: CGPoint, value: String)
    case highlight([CGPoint])
    case step(center: CGPoint, number: Int)

    var tool: AnnotationTool {
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
        }
    }

    func translated(by offset: CGSize) -> AnnotationContent {
        let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
        switch self {
        case .rectangle(let rect):
            return .rectangle(rect.applying(transform))
        case .ellipse(let rect):
            return .ellipse(rect.applying(transform))
        case .line(let start, let end):
            return .line(from: start.applying(transform), to: end.applying(transform))
        case .arrow(let start, let end):
            return .arrow(from: start.applying(transform), to: end.applying(transform))
        case .pen(let points):
            return .pen(points.map { $0.applying(transform) })
        case .mosaic(let points):
            return .mosaic(points.map { $0.applying(transform) })
        case .text(let origin, let value):
            return .text(origin: origin.applying(transform), value: value)
        case .highlight(let points):
            return .highlight(points.map { $0.applying(transform) })
        case .step(let center, let number):
            return .step(center: center.applying(transform), number: number)
        }
    }
}

struct Annotation: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: AnnotationContent
    let parameters: AnnotationToolParameters

    init(
        id: UUID = UUID(),
        content: AnnotationContent,
        parameters: AnnotationToolParameters? = nil
    ) {
        self.id = id
        self.content = content
        self.parameters = parameters ?? content.tool.defaultParameters
    }

    var tool: AnnotationTool { content.tool }

    var bounds: CGRect {
        switch content {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized
        case .line(let start, let end), .arrow(let start, let end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ).insetBy(dx: -parameters.lineWidth / 2, dy: -parameters.lineWidth / 2)
        case .pen(let points), .mosaic(let points), .highlight(let points):
            guard let first = points.first else { return .zero }
            let pointBounds = points.dropFirst().reduce(
                CGRect(origin: first, size: .zero)
            ) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
            return pointBounds.insetBy(dx: -parameters.lineWidth / 2, dy: -parameters.lineWidth / 2)
        case .text(let origin, let value):
            return CGRect(
                origin: origin,
                size: CGSize(
                    width: max(parameters.fontSize, CGFloat(value.count) * parameters.fontSize * 0.6),
                    height: parameters.fontSize * 1.25
                )
            )
        case .step(let center, _):
            let radius = max(parameters.fontSize * 0.75, 12)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    func translated(by offset: CGSize) -> Annotation {
        Annotation(id: id, content: content.translated(by: offset), parameters: parameters)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let radius = max(tolerance, parameters.lineWidth / 2)
        switch content {
        case .rectangle(let rect):
            return rect.standardized.insetBy(dx: -radius, dy: -radius).contains(point)
        case .ellipse(let rect):
            let rect = rect.standardized
            let horizontalRadius = (rect.width / 2) + radius
            let verticalRadius = (rect.height / 2) + radius
            guard horizontalRadius > 0, verticalRadius > 0 else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dx = (point.x - center.x) / horizontalRadius
            let dy = (point.y - center.y) / verticalRadius
            return (dx * dx) + (dy * dy) <= 1
        case .line(let start, let end), .arrow(let start, let end):
            return point.distance(toSegmentFrom: start, to: end) <= radius
        case .pen(let points), .mosaic(let points), .highlight(let points):
            return points.hitPath(at: point, radius: radius)
        case .text(let origin, let value):
            let estimatedWidth = max(parameters.fontSize, CGFloat(value.count) * parameters.fontSize * 0.6)
            let estimatedBounds = CGRect(
                x: origin.x,
                y: origin.y,
                width: estimatedWidth,
                height: parameters.fontSize * 1.25
            )
            return estimatedBounds.insetBy(dx: -radius, dy: -radius).contains(point)
        case .step(let center, _):
            return hypot(point.x - center.x, point.y - center.y) <= max(parameters.fontSize * 0.75, 12) + radius
        }
    }
}

private extension CGPoint {
    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return hypot(x - start.x, y - start.y) }
        let projection = ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared
        let t = min(1, max(0, projection))
        return hypot(x - (start.x + t * dx), y - (start.y + t * dy))
    }
}

private extension Array where Element == CGPoint {
    func hitPath(at point: CGPoint, radius: CGFloat) -> Bool {
        guard let first else { return false }
        if count == 1 {
            return hypot(point.x - first.x, point.y - first.y) <= radius
        }
        return zip(self, dropFirst()).contains { start, end in
            point.distance(toSegmentFrom: start, to: end) <= radius
        }
    }
}
