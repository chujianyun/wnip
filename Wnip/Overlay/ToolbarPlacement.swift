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
