import CoreGraphics

enum OverlaySelectionDrag: Equatable, Sendable {
    case newSelection
    case resize(SelectionHandle)
}

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

    static func selectionDrag(
        at point: CGPoint,
        mode: CaptureMode,
        showsToolbar: Bool,
        selection: CGRect
    ) -> OverlaySelectionDrag? {
        guard mode == .region || showsToolbar else { return nil }
        if let handle = resizeHandle(at: point, selection: selection) {
            return .resize(handle)
        }
        return showsToolbar ? nil : .newSelection
    }

    static func updatedSelection(
        _ selection: SelectionModel,
        drag: OverlaySelectionDrag?,
        from startPoint: CGPoint,
        to currentPoint: CGPoint,
        within bounds: CGRect
    ) -> SelectionModel {
        guard let drag else { return selection }
        var result = selection
        switch drag {
        case .newSelection:
            result.begin(at: startPoint)
            result.update(to: currentPoint, within: bounds)
        case .resize(let handle):
            result.resize(handle: handle, to: currentPoint, within: bounds)
        }
        return result
    }

    static func highlightedRect(
        mode: CaptureMode,
        showsToolbar: Bool,
        selection: CGRect,
        hoveredWindow: CaptureCandidateWindow?,
        displayFrame: CGRect,
        isActiveDisplay: Bool
    ) -> CGRect? {
        if showsToolbar {
            return selection.isEmpty ? nil : selection.standardized
        }
        switch mode {
        case .region:
            return selection.isEmpty ? nil : selection.standardized
        case .window:
            return hoveredWindow?.frame.standardized
        case .fullScreen:
            return isActiveDisplay ? displayFrame.standardized : nil
        }
    }

    static func tracksWindowHover(mode: CaptureMode, showsToolbar: Bool) -> Bool {
        mode == .window && !showsToolbar
    }
}
