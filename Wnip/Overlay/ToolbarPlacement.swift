import CoreGraphics

enum ToolbarPlacement {
    private static let spacing: CGFloat = 8
    private static let displayInset: CGFloat = 8

    static func resolve(
        selection: CGRect,
        visibleFrame: CGRect,
        toolbarSize: CGSize
    ) -> CGRect {
        let selection = selection.standardized
        let safeFrame = visibleFrame.standardized.insetBy(dx: displayInset, dy: displayInset)
        let centeredX = selection.midX - (toolbarSize.width / 2)
        let belowY = selection.minY - spacing - toolbarSize.height
        let aboveY = selection.maxY + spacing

        let proposedY: CGFloat
        if belowY >= safeFrame.minY {
            proposedY = belowY
        } else if aboveY + toolbarSize.height <= safeFrame.maxY {
            proposedY = aboveY
        } else {
            proposedY = selection.minY + spacing
        }

        return CGRect(
            x: clamp(centeredX, minimum: safeFrame.minX, maximum: safeFrame.maxX - toolbarSize.width),
            y: clamp(proposedY, minimum: safeFrame.minY, maximum: safeFrame.maxY - toolbarSize.height),
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}

enum AnnotationParameterControlsPlacement {
    static func resolveLocal(selection: CGRect, canvasSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let globalSelection = CGRect(x: selection.minX, y: canvasSize.height - selection.maxY,
                                     width: selection.width, height: selection.height)
        return OverlayInteractionGeometry.localRect(forGlobalRect: resolve(
            selection: globalSelection, visibleFrame: bounds,
            controlsSize: CGSize(width: 220, height: 36)), in: bounds)
    }

    private static let spacing: CGFloat = 8
    private static let displayInset: CGFloat = 8

    static func resolve(
        selection: CGRect,
        visibleFrame: CGRect,
        controlsSize: CGSize,
        toolbarFrame: CGRect? = nil
    ) -> CGRect {
        let selection = selection.standardized
        let safeFrame = visibleFrame.standardized.insetBy(dx: displayInset, dy: displayInset)
        var aboveY = selection.maxY + spacing + 26
        var belowY = selection.minY - spacing - controlsSize.height
        if let toolbarFrame {
            if toolbarFrame.maxY > selection.maxY { aboveY = max(aboveY, toolbarFrame.maxY + spacing) }
            if toolbarFrame.minY < selection.minY { belowY = min(belowY, toolbarFrame.minY - spacing - controlsSize.height) }
        }

        let proposedOrigin: CGPoint
        if aboveY + controlsSize.height <= safeFrame.maxY {
            proposedOrigin = CGPoint(x: selection.minX, y: aboveY)
        } else if belowY >= safeFrame.minY {
            proposedOrigin = CGPoint(x: selection.minX, y: belowY)
        } else {
            proposedOrigin = CGPoint(
                x: selection.minX + spacing,
                y: selection.maxY - spacing - 26 - controlsSize.height
            )
        }

        return CGRect(
            x: clamp(
                proposedOrigin.x,
                minimum: safeFrame.minX,
                maximum: safeFrame.maxX - controlsSize.width
            ),
            y: clamp(
                proposedOrigin.y,
                minimum: safeFrame.minY,
                maximum: safeFrame.maxY - controlsSize.height
            ),
            width: controlsSize.width,
            height: controlsSize.height
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}

enum PixelBadgePlacement {
    private static let spacing: CGFloat = 4
    private static let displayInset: CGFloat = 4

    static func resolve(
        selection: CGRect,
        visibleBounds: CGRect,
        badgeSize: CGSize
    ) -> CGRect {
        let selection = selection.standardized
        let safeBounds = visibleBounds.standardized.insetBy(dx: displayInset, dy: displayInset)
        let proposedOrigin = CGPoint(
            x: selection.minX,
            y: selection.minY - spacing - badgeSize.height
        )
        return CGRect(
            x: clamp(proposedOrigin.x, minimum: safeBounds.minX, maximum: safeBounds.maxX - badgeSize.width),
            y: clamp(proposedOrigin.y, minimum: safeBounds.minY, maximum: safeBounds.maxY - badgeSize.height),
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}

enum PixelBadgeContent {
    static func label(for selection: CGRect, on display: DisplayDescriptor) -> String {
        let selection = selection.standardized
        let width = Int((selection.width * display.scale).rounded())
        let height = Int((selection.height * display.scale).rounded())
        return "\(width) × \(height) px"
    }
}
