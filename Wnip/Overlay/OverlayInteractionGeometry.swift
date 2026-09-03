import CoreGraphics

enum OverlayInteractionGeometry {
    static func localRect(forGlobalRect rect: CGRect, in displayFrame: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func globalPoint(forLocalPoint point: CGPoint, in displayFrame: CGRect) -> CGPoint {
        CGPoint(
            x: displayFrame.minX + point.x,
            y: displayFrame.maxY - point.y
        )
    }

    static func resizeHandle(
        at point: CGPoint,
        selection: CGRect,
        hitRadius: CGFloat = 8
    ) -> SelectionHandle? {
        guard !selection.standardized.isEmpty else { return nil }
        return resizeHandleCenters(selection: selection).first { _, center in
            hypot(point.x - center.x, point.y - center.y) <= hitRadius
        }?.0
    }

    static func resizeHandleCenters(selection: CGRect) -> [(SelectionHandle, CGPoint)] {
        let selection = selection.standardized
        return [
            (.topLeft, CGPoint(x: selection.minX, y: selection.maxY)),
            (.top, CGPoint(x: selection.midX, y: selection.maxY)),
            (.topRight, CGPoint(x: selection.maxX, y: selection.maxY)),
            (.right, CGPoint(x: selection.maxX, y: selection.midY)),
            (.bottomRight, CGPoint(x: selection.maxX, y: selection.minY)),
            (.bottom, CGPoint(x: selection.midX, y: selection.minY)),
            (.bottomLeft, CGPoint(x: selection.minX, y: selection.minY)),
            (.left, CGPoint(x: selection.minX, y: selection.midY))
        ]
    }

    static func window(
        at point: CGPoint,
        candidatesInFrontToBackOrder windows: [CaptureCandidateWindow]
    ) -> CaptureCandidateWindow? {
        windows.first { $0.frame.standardized.contains(point) }
    }
}
