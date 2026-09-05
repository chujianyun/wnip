import SwiftUI

@MainActor
final class CaptureOverlayViewModel: ObservableObject {
    let display: DisplayDescriptor
    @Published private(set) var visibleFrame: CGRect
    @Published var presentation: OverlayPresentation

    init(display: DisplayDescriptor, visibleFrame: CGRect, presentation: OverlayPresentation) {
        self.display = display
        self.visibleFrame = visibleFrame
        self.presentation = presentation
    }

    func update(presentation: OverlayPresentation, visibleFrame: CGRect) {
        self.presentation = presentation
        self.visibleFrame = visibleFrame
    }
}

struct CaptureOverlayView: View {
    @ObservedObject var viewModel: CaptureOverlayViewModel

    let onActiveDisplay: (UInt32) -> Void
    let onSelectionChanged: (UInt32, SelectionModel) -> Void
    let onSelectionCommitted: (UInt32, SelectionModel) -> Void
    let onWindowHovered: (UInt32, CaptureCandidateWindow?) -> Void
    let onWindowSelected: (UInt32, CaptureCandidateWindow) -> Void
    let onDisplaySelected: (DisplayDescriptor) -> Void
    let onToolbarAction: (OverlayToolbarAction) -> Void

    @State private var selectionDrag: OverlaySelectionDrag?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                interactionSurface
                mask(size: proxy.size)

                if let highlightedRect {
                    selectionBorder(for: highlightedRect)

                    if showsResizeHandles {
                        resizeHandles(for: highlightedRect)
                    }

                    pixelSizeBadge(for: highlightedRect)
                }

                if showsToolbar, let toolbarRect {
                    AnnotationToolbar(onAction: onToolbarAction)
                        .frame(width: toolbarRect.width, height: toolbarRect.height)
                        .position(x: toolbarRect.midX, y: toolbarRect.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color.clear)
    }

    private var interactionSurface: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    handleHover(at: location)
                case .ended:
                    if OverlayInteractionGeometry.tracksWindowHover(
                        mode: viewModel.presentation.mode,
                        showsToolbar: viewModel.presentation.showsToolbar
                    ) {
                        onWindowHovered(viewModel.display.id, nil)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged(handleDragChanged)
                    .onEnded(handleDragEnded)
            )
    }

    private var highlightedGlobalRect: CGRect? {
        let presentation = viewModel.presentation
        let hoveredWindow = presentation.windows.first { $0.id == presentation.hoveredWindowID }
        return OverlayInteractionGeometry.highlightedRect(
            mode: presentation.mode,
            showsToolbar: presentation.showsToolbar,
            selection: presentation.selection.rect,
            hoveredWindow: hoveredWindow,
            displayFrame: viewModel.display.frame,
            isActiveDisplay: presentation.activeDisplayID == viewModel.display.id
        )
    }

    private var highlightedRect: CGRect? {
        guard let globalRect = highlightedGlobalRect else { return nil }
        let localRect = OverlayInteractionGeometry.localRect(
            forGlobalRect: globalRect,
            in: viewModel.display.frame
        )
        let displayBounds = CGRect(origin: .zero, size: viewModel.display.frame.size)
        let clipped = localRect.intersection(displayBounds)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    private var showsResizeHandles: Bool {
        viewModel.presentation.mode == .region || viewModel.presentation.showsToolbar
    }

    private var showsToolbar: Bool {
        viewModel.presentation.showsToolbar &&
            viewModel.presentation.activeDisplayID == viewModel.display.id
    }

    private var toolbarRect: CGRect? {
        guard !viewModel.presentation.selection.rect.isEmpty else { return nil }
        let globalFrame = ToolbarPlacement.resolve(
            selection: viewModel.presentation.selection.rect,
            visibleFrame: viewModel.visibleFrame,
            toolbarSize: AnnotationToolbar.preferredSize
        )
        return OverlayInteractionGeometry.localRect(
            forGlobalRect: globalFrame,
            in: viewModel.display.frame
        )
    }

    private func mask(size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path(CGRect(origin: .zero, size: size))
            if let highlightedRect {
                path.addRect(highlightedRect)
            }
            context.fill(
                path,
                with: .color(.black.opacity(0.48)),
                style: FillStyle(eoFill: true)
            )
        }
        .allowsHitTesting(false)
    }

    private func selectionBorder(for rect: CGRect) -> some View {
        Rectangle()
            .stroke(Color(red: 0.08, green: 0.58, blue: 1), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func resizeHandles(for localRect: CGRect) -> some View {
        let globalRect = highlightedGlobalRect ?? .zero
        ForEach(SelectionHandle.allCases, id: \.self) { handle in
            if let center = OverlayInteractionGeometry.resizeHandleCenters(selection: globalRect)
                .first(where: { $0.0 == handle })?.1 {
                let localCenter = OverlayInteractionGeometry.localRect(
                    forGlobalRect: CGRect(origin: center, size: CGSize(width: 0.01, height: 0.01)),
                    in: viewModel.display.frame
                ).origin
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color(red: 0.08, green: 0.58, blue: 1), lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                    .position(x: localCenter.x, y: localCenter.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private func pixelSizeBadge(for rect: CGRect) -> some View {
        let globalRect = highlightedGlobalRect ?? .zero
        let badgeSize = CGSize(width: 104, height: 22)
        let badgeFrame = PixelBadgePlacement.resolve(
            selection: rect,
            visibleBounds: CGRect(origin: .zero, size: viewModel.display.frame.size),
            badgeSize: badgeSize
        )
        return Text(PixelBadgeContent.label(for: globalRect, on: viewModel.display))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: badgeSize.width, height: badgeSize.height)
            .background(Color(red: 0.08, green: 0.58, blue: 1), in: RoundedRectangle(cornerRadius: 3))
            .position(x: badgeFrame.midX, y: badgeFrame.midY)
            .allowsHitTesting(false)
    }

    private func handleHover(at localPoint: CGPoint) {
        let presentation = viewModel.presentation
        guard OverlayInteractionGeometry.tracksWindowHover(
            mode: presentation.mode,
            showsToolbar: presentation.showsToolbar
        ) else { return }

        onActiveDisplay(viewModel.display.id)
        let globalPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: localPoint,
            in: viewModel.display.frame
        )
        let window = OverlayInteractionGeometry.window(
            at: globalPoint,
            candidatesInFrontToBackOrder: presentation.windows
        )
        guard window?.id != presentation.hoveredWindowID else { return }
        onWindowHovered(viewModel.display.id, window)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let display = viewModel.display
        let currentPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: value.location,
            in: display.frame
        )

        let presentation = viewModel.presentation
        let startPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: value.startLocation,
            in: display.frame
        )
        if selectionDrag == nil {
            selectionDrag = OverlayInteractionGeometry.selectionDrag(
                at: startPoint,
                mode: presentation.mode,
                showsToolbar: presentation.showsToolbar,
                selection: presentation.selection.rect
            )
        }
        if let selectionDrag {
            let selection = OverlayInteractionGeometry.updatedSelection(
                presentation.selection,
                drag: selectionDrag,
                from: startPoint,
                to: currentPoint,
                within: display.frame
            )
            onSelectionChanged(display.id, selection)
            return
        }

        switch presentation.mode {
        case .region:
            break
        case .window, .fullScreen:
            onActiveDisplay(display.id)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer { selectionDrag = nil }
        let display = viewModel.display
        let globalPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: value.location,
            in: display.frame
        )

        if selectionDrag != nil {
            onSelectionCommitted(display.id, viewModel.presentation.selection)
            return
        }

        // Once committed, clicks outside the selection must not pick a new window.
        guard !viewModel.presentation.showsToolbar else { return }

        switch viewModel.presentation.mode {
        case .region:
            break
        case .window:
            if let window = OverlayInteractionGeometry.window(
                at: globalPoint,
                candidatesInFrontToBackOrder: viewModel.presentation.windows
            ) {
                onWindowSelected(display.id, window)
            }
        case .fullScreen:
            onDisplaySelected(display)
        }
    }
}
