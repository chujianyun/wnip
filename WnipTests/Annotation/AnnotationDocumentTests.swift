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

    func testOnlyStrokeToolsExposeLineWidthControl() {
        XCTAssertEqual(
            AnnotationTool.allCases.filter { $0.usesLineWidth },
            [.rectangle, .ellipse, .line, .arrow, .pen, .mosaic, .highlight]
        )
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

    func testArrowheadUsesSameGeometryForBoundsAndHitTesting() {
        let arrow = Annotation(
            content: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 0)),
            parameters: .init(color: .red, lineWidth: 2, fontSize: 18)
        )
        var document = AnnotationDocument()
        document.perform(.add(arrow))
        let pointOnArrowhead = CGPoint(x: 31, y: 5)

        XCTAssertTrue(arrow.bounds.contains(pointOnArrowhead))
        XCTAssertEqual(document.hitTest(pointOnArrowhead, tolerance: 1)?.id, arrow.id)
    }

    func testArrowheadIsCappedForShortThickShaftAndOmittedForNegligibleShaft() {
        let short = AnnotationArrowGeometry(
            start: CGPoint(x: 0, y: 0),
            tip: CGPoint(x: 4, y: 0),
            lineWidth: 10
        )
        let shortHeadLength = hypot(short.tip.x - short.headA.x, short.tip.y - short.headA.y)
        XCTAssertEqual(shortHeadLength, 1.8, accuracy: 0.001)

        let negligible = AnnotationArrowGeometry(
            start: CGPoint(x: 0, y: 0),
            tip: CGPoint(x: 0.25, y: 0),
            lineWidth: 3
        )
        XCTAssertEqual(negligible.headA, negligible.tip)
        XCTAssertEqual(negligible.headB, negligible.tip)
    }

    func testWideTextBoundsUseRenderedFontMeasurement() {
        let annotation = Annotation(
            content: .text(origin: CGPoint(x: 10, y: 20), value: "WWWW"),
            parameters: .init(color: .red, lineWidth: 3, fontSize: 20)
        )

        XCTAssertGreaterThan(annotation.bounds.width, 65)
        XCTAssertTrue(annotation.contains(CGPoint(x: 70, y: 30), tolerance: 0))
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
        var document = AnnotationDocument(
            cropRect: CGRect(x: 0, y: 0, width: 100, height: 80),
            sourceBounds: CGRect(x: 0, y: 0, width: 120, height: 100)
        )

        XCTAssertTrue(document.perform(.crop(CGRect(x: 10, y: 12, width: 60, height: 40))))
        XCTAssertEqual(document.cropRect, CGRect(x: 10, y: 12, width: 60, height: 40))
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.cropRect, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testCropNormalizesToSourceBoundsAndRejectsDisjointRect() {
        var document = AnnotationDocument(
            sourceBounds: CGRect(x: 0, y: 0, width: 100, height: 80)
        )

        XCTAssertFalse(document.perform(.crop(CGRect(x: 120, y: 20, width: 30, height: 30))))
        XCTAssertNil(document.cropRect)
        XCTAssertFalse(document.canUndo)

        XCTAssertTrue(document.perform(.crop(CGRect(x: -10, y: 10, width: 30, height: 40))))
        XCTAssertEqual(document.cropRect, CGRect(x: 0, y: 10, width: 20, height: 40))
        XCTAssertTrue(document.undo())
        XCTAssertNil(document.cropRect)
    }

    func testCropIsRejectedWhenDocumentHasNoSourceBounds() {
        var document = AnnotationDocument()

        XCTAssertFalse(document.perform(.crop(CGRect(x: 10, y: 10, width: 20, height: 20))))
        XCTAssertNil(document.cropRect)
        XCTAssertFalse(document.canUndo)
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

    func testStepNumberExcludesCroppedAwayStepsAndUndoRestoresThem() {
        let visible = Annotation(content: .step(center: CGPoint(x: 20, y: 20), number: 1))
        let croppedAway = Annotation(content: .step(center: CGPoint(x: 120, y: 20), number: 7))
        var document = AnnotationDocument(
            annotations: [visible, croppedAway],
            sourceBounds: CGRect(x: 0, y: 0, width: 160, height: 80)
        )

        XCTAssertTrue(document.perform(.crop(CGRect(x: 0, y: 0, width: 50, height: 50))))
        XCTAssertEqual(document.nextStepNumber, 2)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.nextStepNumber, 8)

        XCTAssertTrue(document.perform(.delete(id: croppedAway.id)))
        XCTAssertEqual(document.nextStepNumber, 2)
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.nextStepNumber, 8)
    }
}

final class AnnotationCanvasTransformTests: XCTestCase {
    func testTwoToOneCropAspectFitsCenteredInOnePointFiveToOneViewport() throws {
        let transform = try XCTUnwrap(AnnotationCanvasTransform(
            sourceBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            cropRect: CGRect(x: 50, y: 20, width: 100, height: 50),
            canvasSize: CGSize(width: 300, height: 200)
        ))

        XCTAssertEqual(transform.visibleSourceRect, CGRect(x: 50, y: 20, width: 100, height: 50))
        XCTAssertEqual(transform.canvasPoint(forSourcePoint: CGPoint(x: 50, y: 20)), CGPoint(x: 0, y: 25))
        XCTAssertEqual(transform.canvasPoint(forSourcePoint: CGPoint(x: 150, y: 70)), CGPoint(x: 300, y: 175))
        XCTAssertEqual(transform.visibleCanvasRect, CGRect(x: 0, y: 25, width: 300, height: 150))
        XCTAssertEqual(transform.sourcePoint(forCanvasPoint: CGPoint(x: 150, y: 100)), CGPoint(x: 100, y: 45))
        XCTAssertEqual(transform.canvasLength(forSourceLength: 2), 6)
        XCTAssertEqual(
            transform.canvasRect(forSourceRect: CGRect(x: 75, y: 30, width: 50, height: 20)),
            CGRect(x: 75, y: 55, width: 150, height: 60)
        )
        XCTAssertEqual(
            transform.sourceImageFrameInCanvas,
            CGRect(x: -150, y: -35, width: 600, height: 300)
        )
    }

    func testTransformConvertsSourceAnnotationGeometryToCanvasGeometry() throws {
        let transform = try XCTUnwrap(AnnotationCanvasTransform(
            sourceBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            cropRect: CGRect(x: 50, y: 20, width: 100, height: 50),
            canvasSize: CGSize(width: 300, height: 200)
        ))
        let source = Annotation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            content: .line(from: CGPoint(x: 75, y: 30), to: CGPoint(x: 125, y: 50)),
            parameters: AnnotationToolParameters(color: .red, lineWidth: 2, fontSize: 18)
        )

        let canvas = transform.canvasAnnotation(source)

        XCTAssertEqual(canvas.id, source.id)
        XCTAssertEqual(
            canvas.content,
            .line(from: CGPoint(x: 75, y: 55), to: CGPoint(x: 225, y: 115))
        )
        XCTAssertEqual(canvas.parameters.lineWidth, 6)
        XCTAssertEqual(canvas.parameters.fontSize, 54)
    }

    func testTransformRejectsDisjointCropInsteadOfShowingFullSource() {
        XCTAssertNil(AnnotationCanvasTransform(
            sourceBounds: CGRect(x: 0, y: 0, width: 100, height: 80),
            cropRect: CGRect(x: 120, y: 10, width: 20, height: 20),
            canvasSize: CGSize(width: 300, height: 200)
        ))
    }

    func testTextRenderLayoutUsesExactlyTheModelTextBounds() throws {
        let annotation = Annotation(
            content: .text(origin: CGPoint(x: 10, y: 20), value: "WWWW"),
            parameters: .init(color: .red, lineWidth: 3, fontSize: 20)
        )

        let layout = try XCTUnwrap(AnnotationCanvasTextLayout(annotation: annotation))

        XCTAssertEqual(layout.renderedFrame, annotation.bounds)
        XCTAssertEqual(layout.value, "WWWW")
        XCTAssertEqual(layout.fontSize, 20)
        XCTAssertGreaterThan(layout.renderedFrame.width, 65)
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
        model.selectForMoving()

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

    func testDrawingToolCreatesOverlappingAnnotationInsteadOfMovingExistingOne() {
        let existing = Annotation(content: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let model = AnnotationCanvasModel(document: AnnotationDocument(annotations: [existing]))
        model.selectTool(.ellipse)

        model.pointerDown(at: CGPoint(x: 20, y: 30))
        model.pointerDragged(to: CGPoint(x: 60, y: 70))
        model.pointerUp(at: CGPoint(x: 60, y: 70))

        XCTAssertEqual(model.document.annotations.map(\.content), [
            .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)),
            .ellipse(CGRect(x: 20, y: 30, width: 40, height: 40))
        ])
    }

    func testGestureLifecycleKeepsFirstNonzeroAndReturnToOriginFreehandSamples() {
        let model = AnnotationCanvasModel()
        model.selectTool(.pen)
        let start = CGPoint(x: 10, y: 10)

        model.gestureChanged(startLocation: start, location: CGPoint(x: 20, y: 15))
        model.gestureChanged(startLocation: start, location: start)
        model.gestureChanged(startLocation: start, location: CGPoint(x: 30, y: 25))
        model.gestureEnded(startLocation: start, location: CGPoint(x: 35, y: 30))

        XCTAssertEqual(model.document.annotations.map(\.content), [
            .pen([
                start,
                CGPoint(x: 20, y: 15),
                start,
                CGPoint(x: 30, y: 25),
                CGPoint(x: 35, y: 30)
            ])
        ])
    }

    func testGestureLifecycleDoesNotRestartMoveWhenPointerReturnsToOrigin() {
        let annotation = Annotation(content: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))
        let model = AnnotationCanvasModel(document: AnnotationDocument(annotations: [annotation]))
        model.selectForMoving()
        let start = CGPoint(x: 15, y: 15)

        model.gestureChanged(startLocation: start, location: CGPoint(x: 25, y: 20))
        model.gestureChanged(startLocation: start, location: start)
        model.gestureChanged(startLocation: start, location: CGPoint(x: 35, y: 25))
        model.gestureEnded(startLocation: start, location: CGPoint(x: 35, y: 25))

        XCTAssertEqual(model.document.annotations.map(\.content), [
            .rectangle(CGRect(x: 30, y: 20, width: 20, height: 20))
        ])
    }

    func testDegenerateGesturesDoNotAddAnnotationsOrUndoHistory() {
        let tools: [AnnotationTool] = [
            .rectangle, .ellipse, .line, .arrow, .pen, .mosaic, .highlight
        ]

        for tool in tools {
            let model = AnnotationCanvasModel()
            model.selectTool(tool)
            let point = CGPoint(x: 20, y: 20)

            model.gestureChanged(startLocation: point, location: point)
            model.gestureEnded(startLocation: point, location: point)

            XCTAssertEqual(model.document.annotations, [], "Unexpected annotation for \(tool)")
            XCTAssertFalse(model.undo(), "Unexpected undo history for \(tool)")
        }
    }

    func testArrowPointerDownPreviewHasNoArrowheadForZeroLengthShaft() throws {
        let model = AnnotationCanvasModel()
        model.selectTool(.arrow)

        model.pointerDown(at: CGPoint(x: 20, y: 20))

        let geometry = try XCTUnwrap(model.previewAnnotation?.arrowGeometry)
        XCTAssertEqual(geometry.start, geometry.tip)
        XCTAssertEqual(geometry.headA, geometry.tip)
        XCTAssertEqual(geometry.headB, geometry.tip)
    }

    func testMoveRenderItemsReplaceCommittedOriginalWithPreview() {
        let moving = Annotation(content: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))
        let untouched = Annotation(content: .ellipse(CGRect(x: 60, y: 60, width: 20, height: 20)))
        let model = AnnotationCanvasModel(document: AnnotationDocument(annotations: [moving, untouched]))
        model.selectForMoving()

        model.pointerDown(at: CGPoint(x: 15, y: 15))
        model.pointerDragged(to: CGPoint(x: 25, y: 20))

        XCTAssertEqual(model.renderItems, [
            AnnotationCanvasRenderItem(
                annotation: moving.translated(by: CGSize(width: 10, height: 5)),
                isPreview: true
            ),
            AnnotationCanvasRenderItem(annotation: untouched, isPreview: false)
        ])
        XCTAssertEqual(model.renderItems.map(\.annotation.id), [moving.id, untouched.id])
    }

    func testCursorUpdatesWhenToolAndModeChangeWhilePointerStaysInside() {
        let annotation = Annotation(content: .rectangle(CGRect(x: 0, y: 0, width: 30, height: 30)))
        let model = AnnotationCanvasModel(document: AnnotationDocument(annotations: [annotation]))
        var state = AnnotationCanvasCursorState()

        state.setPointerInside(true, activeCursor: model.cursorKind)
        XCTAssertEqual(state.displayedCursor, .crosshair)

        model.selectTool(.text)
        state.activeCursorChanged(model.cursorKind)
        XCTAssertEqual(state.displayedCursor, .iBeam)

        model.selectForMoving()
        state.activeCursorChanged(model.cursorKind)
        XCTAssertEqual(state.displayedCursor, .openHand)

        model.pointerDown(at: CGPoint(x: 10, y: 10))
        state.activeCursorChanged(model.cursorKind)
        XCTAssertEqual(state.displayedCursor, .closedHand)

        state.setPointerInside(false, activeCursor: model.cursorKind)
        XCTAssertEqual(state.displayedCursor, .arrow)
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
