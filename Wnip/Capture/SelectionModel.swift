import CoreGraphics

enum SelectionHandle: CaseIterable, Equatable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct SelectionModel: Equatable, Sendable {
    static let minimumSize: CGFloat = 8

    private var anchor: CGPoint?
    private(set) var rect: CGRect

    init(rect: CGRect = .zero) {
        self.rect = rect.standardized
    }

    mutating func begin(at point: CGPoint) {
        anchor = point
        rect = CGRect(origin: point, size: .zero)
    }

    mutating func update(to point: CGPoint, within bounds: CGRect) {
        guard let anchor else { return }

        let clampedAnchor = clamp(anchor, to: bounds)
        let clampedPoint = clamp(point, to: bounds)
        rect = minimumRect(from: clampedAnchor, to: clampedPoint, within: bounds)
    }

    mutating func resize(_ handle: SelectionHandle, to point: CGPoint, within bounds: CGRect) {
        guard !rect.isEmpty else { return }

        let point = clamp(point, to: bounds)
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = constrainedMinimum(point.x, maximum: maxX, boundMinimum: bounds.minX)
            maxY = constrainedMaximum(point.y, minimum: minY, boundMaximum: bounds.maxY)
        case .top:
            maxY = constrainedMaximum(point.y, minimum: minY, boundMaximum: bounds.maxY)
        case .topRight:
            maxX = constrainedMaximum(point.x, minimum: minX, boundMaximum: bounds.maxX)
            maxY = constrainedMaximum(point.y, minimum: minY, boundMaximum: bounds.maxY)
        case .right:
            maxX = constrainedMaximum(point.x, minimum: minX, boundMaximum: bounds.maxX)
        case .bottomRight:
            maxX = constrainedMaximum(point.x, minimum: minX, boundMaximum: bounds.maxX)
            minY = constrainedMinimum(point.y, maximum: maxY, boundMinimum: bounds.minY)
        case .bottom:
            minY = constrainedMinimum(point.y, maximum: maxY, boundMinimum: bounds.minY)
        case .bottomLeft:
            minX = constrainedMinimum(point.x, maximum: maxX, boundMinimum: bounds.minX)
            minY = constrainedMinimum(point.y, maximum: maxY, boundMinimum: bounds.minY)
        case .left:
            minX = constrainedMinimum(point.x, maximum: maxX, boundMinimum: bounds.minX)
        }

        rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func pixelRect(on display: DisplayDescriptor) -> CGRect {
        display.pixelRect(forGlobalRect: rect)
    }

    private func minimumRect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let horizontalDirection: CGFloat = end.x >= start.x ? 1 : -1
        let verticalDirection: CGFloat = end.y >= start.y ? 1 : -1
        let minimumEnd = CGPoint(
            x: constrainedDragEndpoint(end.x, start: start.x, direction: horizontalDirection, bounds: bounds, axis: \.x),
            y: constrainedDragEndpoint(end.y, start: start.y, direction: verticalDirection, bounds: bounds, axis: \.y)
        )
        let horizontalSpan = minimumSpan(
            from: min(start.x, minimumEnd.x),
            to: max(start.x, minimumEnd.x),
            direction: horizontalDirection,
            bounds: bounds.minX...bounds.maxX
        )
        let verticalSpan = minimumSpan(
            from: min(start.y, minimumEnd.y),
            to: max(start.y, minimumEnd.y),
            direction: verticalDirection,
            bounds: bounds.minY...bounds.maxY
        )
        return CGRect(
            x: horizontalSpan.lowerBound,
            y: verticalSpan.lowerBound,
            width: horizontalSpan.upperBound - horizontalSpan.lowerBound,
            height: verticalSpan.upperBound - verticalSpan.lowerBound
        )
    }

    private func constrainedDragEndpoint(
        _ end: CGFloat,
        start: CGFloat,
        direction: CGFloat,
        bounds: CGRect,
        axis: KeyPath<CGPoint, CGFloat>
    ) -> CGFloat {
        let boundMinimum = axis == \.x ? bounds.minX : bounds.minY
        let boundMaximum = axis == \.x ? bounds.maxX : bounds.maxY
        let desired = start + (direction * Self.minimumSize)
        if direction > 0 {
            return min(max(end, desired), boundMaximum)
        }
        return max(min(end, desired), boundMinimum)
    }

    private func constrainedMinimum(_ value: CGFloat, maximum: CGFloat, boundMinimum: CGFloat) -> CGFloat {
        max(boundMinimum, min(value, maximum - Self.minimumSize))
    }

    private func constrainedMaximum(_ value: CGFloat, minimum: CGFloat, boundMaximum: CGFloat) -> CGFloat {
        min(boundMaximum, max(value, minimum + Self.minimumSize))
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func minimumSpan(
        from lower: CGFloat,
        to upper: CGFloat,
        direction: CGFloat,
        bounds: ClosedRange<CGFloat>
    ) -> ClosedRange<CGFloat> {
        let minimumSize = min(Self.minimumSize, bounds.upperBound - bounds.lowerBound)
        guard upper - lower < minimumSize else { return lower...upper }

        if direction > 0 {
            let adjustedUpper = min(bounds.upperBound, lower + minimumSize)
            return max(bounds.lowerBound, adjustedUpper - minimumSize)...adjustedUpper
        }

        let adjustedLower = max(bounds.lowerBound, upper - minimumSize)
        return adjustedLower...min(bounds.upperBound, adjustedLower + minimumSize)
    }
}
