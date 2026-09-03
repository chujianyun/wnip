import CoreGraphics
import Foundation

enum AnnotationCommand: Equatable, Sendable {
    case add(Annotation)
    case move(id: UUID, offset: CGSize)
    case delete(id: UUID)
    case crop(CGRect)
}

struct AnnotationDocument: Equatable, Sendable {
    private struct Snapshot: Equatable, Sendable {
        let annotations: [Annotation]
        let cropRect: CGRect?
    }

    private struct HistoryEntry: Equatable, Sendable {
        let command: AnnotationCommand
        let before: Snapshot
    }

    private(set) var annotations: [Annotation]
    private(set) var cropRect: CGRect?
    private(set) var sourceBounds: CGRect?
    private var undoStack: [HistoryEntry] = []

    init(
        annotations: [Annotation] = [],
        cropRect: CGRect? = nil,
        sourceBounds: CGRect? = nil
    ) {
        self.annotations = annotations
        let normalizedSourceBounds = sourceBounds?.standardized
        self.sourceBounds = normalizedSourceBounds
        self.cropRect = Self.normalizedCrop(cropRect, within: normalizedSourceBounds)
    }

    var canUndo: Bool { !undoStack.isEmpty }

    var nextStepNumber: Int {
        annotations.compactMap { annotation in
            guard case .step(_, let number) = annotation.content else { return nil }
            if let cropRect, !annotation.bounds.intersects(cropRect) {
                return nil
            }
            return number
        }.max().map { $0 + 1 } ?? 1
    }

    @discardableResult
    mutating func perform(_ command: AnnotationCommand) -> Bool {
        let before = Snapshot(annotations: annotations, cropRect: cropRect)
        guard apply(command) else { return false }
        undoStack.append(HistoryEntry(command: command, before: before))
        return true
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        annotations = entry.before.annotations
        cropRect = entry.before.cropRect
        return true
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Annotation? {
        if let cropRect, !cropRect.contains(point) {
            return nil
        }
        return annotations.reversed().first { $0.contains(point, tolerance: max(0, tolerance)) }
    }

    private mutating func apply(_ command: AnnotationCommand) -> Bool {
        switch command {
        case .add(let annotation):
            guard annotation.hasRenderableContent,
                  !annotations.contains(where: { $0.id == annotation.id }) else { return false }
            annotations.append(annotation)
        case .move(let id, let offset):
            guard offset != .zero,
                  let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
            annotations[index] = annotations[index].translated(by: offset)
        case .delete(let id):
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
            annotations.remove(at: index)
        case .crop(let rect):
            guard let normalized = Self.normalizedCrop(rect, within: sourceBounds),
                  normalized != cropRect else { return false }
            cropRect = normalized
        }
        return true
    }

    private static func normalizedCrop(_ crop: CGRect?, within sourceBounds: CGRect?) -> CGRect? {
        guard var normalized = crop?.standardized,
              !normalized.isEmpty,
              let sourceBounds else { return nil }
        normalized = normalized.intersection(sourceBounds)
        guard !normalized.isNull, !normalized.isEmpty else { return nil }
        return normalized
    }
}
