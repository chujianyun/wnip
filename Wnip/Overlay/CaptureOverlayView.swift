import SwiftUI

@MainActor
final class CaptureOverlayViewModel: ObservableObject {
    let display: DisplayDescriptor
    let visibleFrame: CGRect
    @Published var presentation: OverlayPresentation

    init(display: DisplayDescriptor, visibleFrame: CGRect, presentation: OverlayPresentation) {
        self.display = display
        self.visibleFrame = visibleFrame
        self.presentation = presentation
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

    @State private var regionDrag: RegionDrag?

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
                    if viewModel.presentation.mode == .window {
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
        switch presentation.mode {
        case .region:
            return presentation.selection.rect.isEmpty ? nil : presentation.selection.rect
        case .window:
            return presentation.windows.first(where: { $0.id == presentation.hoveredWindowID })?.frame
                ?? (presentation.selection.rect.isEmpty ? nil : presentation.selection.rect)
        case .fullScreen:
            return presentation.activeDisplayID == viewModel.display.id ? viewModel.display.frame : nil
        }
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
        let width = Int((globalRect.width * viewModel.display.scale).rounded())
        let height = Int((globalRect.height * viewModel.display.scale).rounded())
        return Text("\(width) × \(height) px")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(red: 0.08, green: 0.58, blue: 1), in: RoundedRectangle(cornerRadius: 3))
            .fixedSize()
            .position(x: max(rect.minX + 48, 48), y: max(rect.minY - 12, 12))
            .allowsHitTesting(false)
    }

    private func handleHover(at localPoint: CGPoint) {
        let presentation = viewModel.presentation
        guard presentation.mode == .window else { return }

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

        switch viewModel.presentation.mode {
        case .region:
            var selection = viewModel.presentation.selection
            if regionDrag == nil {
                let startPoint = OverlayInteractionGeometry.globalPoint(
                    forLocalPoint: value.startLocation,
                    in: display.frame
                )
                if let handle = OverlayInteractionGeometry.resizeHandle(
                    at: startPoint,
                    selection: selection.rect
                ) {
                    regionDrag = .resize(handle)
                } else {
                    regionDrag = .newSelection
                    selection.begin(at: startPoint)
                }
            }

            switch regionDrag {
            case .resize(let handle):
                selection.resize(handle: handle, to: currentPoint, within: display.frame)
            case .newSelection:
                selection.update(to: currentPoint, within: display.frame)
            case nil:
                return
            }
            onSelectionChanged(display.id, selection)

        case .window, .fullScreen:
            onActiveDisplay(display.id)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer { regionDrag = nil }
        let display = viewModel.display
        let globalPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: value.location,
            in: display.frame
        )

        switch viewModel.presentation.mode {
        case .region:
            onSelectionCommitted(display.id, viewModel.presentation.selection)
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

private enum RegionDrag {
    case newSelection
    case resize(SelectionHandle)
}
