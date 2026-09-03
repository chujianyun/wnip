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
