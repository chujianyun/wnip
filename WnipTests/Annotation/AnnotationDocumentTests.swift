import XCTest
@testable import Wnip

final class AnnotationDocumentTests: XCTestCase {
    func testDefaultParametersAreDeterministicForEveryTool() {
        let cases: [(AnnotationTool, AnnotationToolParameters)] = [
            (.rectangle, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.ellipse, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.line, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.arrow, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.pen, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.mosaic, AnnotationToolParameters(color: .init(red: 0, green: 0, blue: 0, alpha: 0), lineWidth: 18, fontSize: 18)),
            (.text, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18)),
            (.highlight, AnnotationToolParameters(color: .init(red: 1, green: 0.84, blue: 0, alpha: 0.38), lineWidth: 16, fontSize: 18)),
            (.step, AnnotationToolParameters(color: .init(red: 0.95, green: 0.16, blue: 0.22, alpha: 1), lineWidth: 3, fontSize: 18))
        ]

        XCTAssertEqual(AnnotationTool.allCases.count, 9)
        for (tool, expected) in cases {
            XCTAssertEqual(tool.defaultParameters, expected, "Unexpected defaults for \(tool)")
        }
    }

    func testHitTestReturnsTopmostAnnotationContainingPoint() {
        let bottom = Annotation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            content: .rectangle(CGRect(x: 10, y: 10, width: 40, height: 40)),
            parameters: .init(color: .red, lineWidth: 3, fontSize: 18)
        )
        let top = Annotation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            content: .ellipse(CGRect(x: 20, y: 20, width: 40, height: 40)),
            parameters: .init(color: .red, lineWidth: 3, fontSize: 18)
        )
        var document = AnnotationDocument()
        document.perform(.add(bottom))
        document.perform(.add(top))

        XCTAssertEqual(document.hitTest(CGPoint(x: 30, y: 30))?.id, top.id)
        XCTAssertEqual(document.hitTest(CGPoint(x: 12, y: 12))?.id, bottom.id)
        XCTAssertNil(document.hitTest(CGPoint(x: 80, y: 80)))
    }

    func testLineHitTestingUsesDistanceRatherThanOnlyBoundingBox() {
        let line = Annotation(
            content: .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50)),
            parameters: .init(color: .red, lineWidth: 2, fontSize: 18)
        )
        var document = AnnotationDocument()
        document.perform(.add(line))

        XCTAssertEqual(document.hitTest(CGPoint(x: 31, y: 29), tolerance: 3)?.id, line.id)
        XCTAssertNil(document.hitTest(CGPoint(x: 10, y: 50), tolerance: 3))
    }

    func testUndoAddRemovesAddedAnnotation() {
        let annotation = Annotation(content: .rectangle(CGRect(x: 4, y: 5, width: 20, height: 30)))
        var document = AnnotationDocument()

        XCTAssertTrue(document.perform(.add(annotation)))
        XCTAssertEqual(document.annotations, [annotation])
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations, [])
        XCTAssertFalse(document.undo())
    }

    func testUndoMoveRestoresOriginalGeometry() {
        let annotation = Annotation(content: .ellipse(CGRect(x: 10, y: 20, width: 30, height: 40)))
        var document = AnnotationDocument(annotations: [annotation])

        XCTAssertTrue(document.perform(.move(id: annotation.id, offset: CGSize(width: 7, height: -3))))
        XCTAssertEqual(document.annotations[0].content, .ellipse(CGRect(x: 17, y: 17, width: 30, height: 40)))
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations, [annotation])
    }

    func testUndoDeleteRestoresOriginalStackingOrder() {
        let first = Annotation(content: .rectangle(CGRect(x: 0, y: 0, width: 20, height: 20)))
        let second = Annotation(content: .ellipse(CGRect(x: 5, y: 5, width: 20, height: 20)))
        var document = AnnotationDocument(annotations: [first, second])

        XCTAssertTrue(document.perform(.delete(id: first.id)))
        XCTAssertEqual(document.annotations, [second])
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations, [first, second])
    }

    func testUndoCropRestoresPreviousCrop() {
        var document = AnnotationDocument(cropRect: CGRect(x: 0, y: 0, width: 100, height: 80))

        XCTAssertTrue(document.perform(.crop(CGRect(x: 10, y: 12, width: 60, height: 40))))
        XCTAssertEqual(document.cropRect, CGRect(x: 10, y: 12, width: 60, height: 40))
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.cropRect, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testStepNumberUsesNextVisibleNumberAfterUndo() {
        let first = Annotation(content: .step(center: CGPoint(x: 10, y: 10), number: 1))
        let second = Annotation(content: .step(center: CGPoint(x: 30, y: 10), number: 2))
        var document = AnnotationDocument()

        document.perform(.add(first))
        document.perform(.add(second))
        XCTAssertEqual(document.nextStepNumber, 3)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.nextStepNumber, 2)
    }

    func testStepNumberUsesMaximumVisibleNumberNotAnnotationCount() {
        let step = Annotation(content: .step(center: CGPoint(x: 10, y: 10), number: 4))
        let rectangle = Annotation(content: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        let document = AnnotationDocument(annotations: [step, rectangle])

        XCTAssertEqual(document.nextStepNumber, 5)
    }
}

@MainActor
final class AnnotationCanvasInteractionTests: XCTestCase {
    func testToolbarActionsDispatchToAllNineAnnotationTools() {
        let cases: [(OverlayToolbarAction, AnnotationTool)] = [
            (.rectangle, .rectangle),
            (.ellipse, .ellipse),
            (.line, .line),
            (.arrow, .arrow),
            (.pen, .pen),
            (.mosaic, .mosaic),
            (.text, .text),
            (.highlight, .highlight),
            (.step, .step)
        ]
        let model = AnnotationCanvasModel()

        for (action, expectedTool) in cases {
            XCTAssertTrue(model.handleToolbarAction(action))
            XCTAssertEqual(model.selectedTool, expectedTool)
            XCTAssertEqual(model.parameters, expectedTool.defaultParameters)
        }

        XCTAssertFalse(model.handleToolbarAction(.copy))
        XCTAssertEqual(model.selectedTool, .step)
    }

    func testShapeDragOnlyCommitsToDocumentOnMouseUp() {
        let model = AnnotationCanvasModel()
        model.selectTool(.rectangle)

        model.pointerDown(at: CGPoint(x: 50, y: 45))
        model.pointerDragged(to: CGPoint(x: 10, y: 15))

        XCTAssertEqual(model.document.annotations, [])
        XCTAssertEqual(
            model.previewAnnotation?.content,
            .rectangle(CGRect(x: 10, y: 15, width: 40, height: 30))
        )

        model.pointerUp(at: CGPoint(x: 10, y: 15))

        XCTAssertEqual(model.document.annotations.count, 1)
        XCTAssertEqual(
            model.document.annotations[0].content,
            .rectangle(CGRect(x: 10, y: 15, width: 40, height: 30))
        )
        XCTAssertNil(model.previewAnnotation)
    }

    func testPenSamplesDragAndCommitsOneCommandOnMouseUp() {
        let model = AnnotationCanvasModel()
        model.selectTool(.pen)

        model.pointerDown(at: CGPoint(x: 2, y: 3))
        model.pointerDragged(to: CGPoint(x: 5, y: 8))
        model.pointerDragged(to: CGPoint(x: 9, y: 13))

        XCTAssertEqual(model.document.annotations, [])
        XCTAssertEqual(
            model.previewAnnotation?.content,
            .pen([CGPoint(x: 2, y: 3), CGPoint(x: 5, y: 8), CGPoint(x: 9, y: 13)])
        )

        model.pointerUp(at: CGPoint(x: 12, y: 14))

        XCTAssertEqual(
            model.document.annotations[0].content,
            .pen([
                CGPoint(x: 2, y: 3),
                CGPoint(x: 5, y: 8),
                CGPoint(x: 9, y: 13),
                CGPoint(x: 12, y: 14)
            ])
        )
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.document.annotations, [])
    }

    func testDraggingExistingAnnotationCommitsMoveOnlyOnMouseUp() {
        let annotation = Annotation(content: .rectangle(CGRect(x: 10, y: 10, width: 30, height: 20)))
        let model = AnnotationCanvasModel(document: AnnotationDocument(annotations: [annotation]))

        model.pointerDown(at: CGPoint(x: 20, y: 20))
        model.pointerDragged(to: CGPoint(x: 28, y: 16))

        XCTAssertEqual(model.document.annotations, [annotation])
        XCTAssertEqual(
            model.previewAnnotation?.content,
            .rectangle(CGRect(x: 18, y: 6, width: 30, height: 20))
        )

        model.pointerUp(at: CGPoint(x: 28, y: 16))

        XCTAssertEqual(
            model.document.annotations[0].content,
            .rectangle(CGRect(x: 18, y: 6, width: 30, height: 20))
        )
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.document.annotations, [annotation])
    }

    func testTextToolStartsEditingOnMouseUpAndCommitsEnteredText() {
        let model = AnnotationCanvasModel()
        model.selectTool(.text)

        model.pointerDown(at: CGPoint(x: 24, y: 30))
        model.pointerUp(at: CGPoint(x: 24, y: 30))

        XCTAssertEqual(model.textEditorOrigin, CGPoint(x: 24, y: 30))
        XCTAssertEqual(model.document.annotations, [])

        XCTAssertTrue(model.commitText("Release candidate"))
        XCTAssertEqual(
            model.document.annotations[0].content,
            .text(origin: CGPoint(x: 24, y: 30), value: "Release candidate")
        )
        XCTAssertNil(model.textEditorOrigin)
    }

    func testStepToolUsesDocumentVisibleNumberAtCommitTime() {
        let model = AnnotationCanvasModel()
        model.selectTool(.step)

        model.pointerDown(at: CGPoint(x: 12, y: 12))
        model.pointerUp(at: CGPoint(x: 12, y: 12))
        model.pointerDown(at: CGPoint(x: 42, y: 12))
        model.pointerUp(at: CGPoint(x: 42, y: 12))
        XCTAssertEqual(model.document.annotations.map(\.content), [
            .step(center: CGPoint(x: 12, y: 12), number: 1),
            .step(center: CGPoint(x: 42, y: 12), number: 2)
        ])

        XCTAssertTrue(model.undo())
        model.pointerDown(at: CGPoint(x: 72, y: 12))
        model.pointerUp(at: CGPoint(x: 72, y: 12))

        XCTAssertEqual(
            model.document.annotations.last?.content,
            .step(center: CGPoint(x: 72, y: 12), number: 2)
        )
    }
}
