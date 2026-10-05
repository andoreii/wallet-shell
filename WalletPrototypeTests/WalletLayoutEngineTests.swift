// WalletLayoutEngineTests.swift
// Checks the geometry, motion state, and edge cases that keep the shell stable.

import XCTest
@testable import WalletPrototype

// These tests protect the measurements and paths used by every visible transition.
final class WalletLayoutEngineTests: XCTestCase {
    func testReferenceDeviceMetrics() {
        let phone14 = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        XCTAssertEqual(phone14.horizontalInset, 20, accuracy: 0.001)
        XCTAssertEqual(phone14.cardWidth, 350, accuracy: 0.001)

        let phone17Pro = WalletMetrics(viewport: CGSize(width: 402, height: 874), cardCount: 4)
        XCTAssertEqual(phone17Pro.horizontalInset, 16, accuracy: 0.001)
        XCTAssertEqual(phone17Pro.cardWidth, 370, accuracy: 0.001)
    }

    func testCollapsedFramesUseStableOverlap() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)

        XCTAssertEqual(engine.collapsedCardFrame(index: 0).minY, 0, accuracy: 0.001)
        XCTAssertEqual(engine.collapsedCardFrame(index: 1).minY, metrics.cardOverlap, accuracy: 0.001)
        XCTAssertEqual(engine.collapsedCardFrame(index: 3).maxY, metrics.stackHeight, accuracy: 0.001)
    }

    func testStartupItemsShareOneOffscreenOriginAndFanIntoTheirSlots() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)
        let originY = metrics.viewport.height + 8

        for index in 0..<4 {
            let restingY = metrics.headerHeight
                + metrics.headerBottomSpacing
                + CGFloat(index) * metrics.cardOverlap
            XCTAssertEqual(
                restingY + engine.startupCardOffset(index: index),
                originY,
                accuracy: 0.001
            )
        }

        let passRestingY = metrics.headerHeight
            + metrics.headerBottomSpacing
            + metrics.stackHeight
            + metrics.passTopSpacing
        XCTAssertEqual(
            passRestingY + engine.startupPassOffset(),
            originY,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            engine.startupCardOffset(index: 0),
            engine.startupCardOffset(index: 3)
        )
    }

    func testReorderDestinationClampsToCardRange() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)

        XCTAssertEqual(engine.reorderIndex(currentIndex: 1, translation: -500, cardCount: 4), 0)
        XCTAssertEqual(engine.reorderIndex(currentIndex: 1, translation: 500, cardCount: 4), 3)
        XCTAssertEqual(engine.reorderIndex(currentIndex: 1, translation: metrics.cardOverlap, cardCount: 4), 2)
    }

    func testNeighborDisplacementTracksDestination() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)

        XCTAssertEqual(engine.displacedOffset(index: 2, sourceIndex: 0, destinationIndex: 3), -metrics.cardOverlap)
        XCTAssertEqual(engine.displacedOffset(index: 0, sourceIndex: 3, destinationIndex: 0), metrics.cardOverlap)
        XCTAssertEqual(engine.displacedOffset(index: 3, sourceIndex: 0, destinationIndex: 2), 0)
    }

    func testSelectionOffsetsKeepBackgroundCardsWithSelectedCard() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)
        let selectedTravel = engine.selectedCardTravel(index: 2, browserScrollOffset: 0)
        let backgroundTravel = engine.selectionOffset(
            index: 0,
            selectedIndex: 2,
            progress: 1,
            browserScrollOffset: 0
        )
        let foregroundTravel = engine.selectionOffset(
            index: 3,
            selectedIndex: 2,
            progress: 1,
            browserScrollOffset: 0
        )

        XCTAssertLessThan(selectedTravel, 0)
        XCTAssertLessThan(backgroundTravel, 0)
        XCTAssertLessThan(abs(backgroundTravel), abs(selectedTravel))
        XCTAssertGreaterThan(foregroundTravel, 0)

        let backgroundFinalMinY = metrics.headerHeight
            + metrics.headerBottomSpacing
            + backgroundTravel
        let selectedFinalMinY = metrics.headerHeight + metrics.detailTopSpacing
        XCTAssertGreaterThanOrEqual(backgroundFinalMinY, selectedFinalMinY)
    }

    func testCardDetailContentUsesExactSelectedCardTravel() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)

        for index in 0..<4 {
            let cardTravel = engine.selectedCardTravel(index: index, browserScrollOffset: 0)
            let contentOffset = engine.cardDetailContentInitialOffset(index: index, browserScrollOffset: 0)
            XCTAssertEqual(contentOffset, -cardTravel, accuracy: 0.001)
            XCTAssertEqual(
                engine.cardDetailTopInitialOffset(index: index, browserScrollOffset: 0),
                contentOffset,
                accuracy: 0.001
            )
        }
    }

    func testPassDetailContentTracksExpandingPassBottomEdge() {
        let metrics = WalletMetrics(viewport: CGSize(width: 402, height: 874), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)
        let sourceBottom = metrics.headerHeight
            + metrics.headerBottomSpacing
            + metrics.stackHeight
            + metrics.passTopSpacing
            + metrics.passHeight
        let destinationBottom = metrics.headerHeight
            + metrics.detailTopSpacing
            + metrics.detailPassHeight

        XCTAssertEqual(
            engine.passDetailContentInitialOffset(browserScrollOffset: 0),
            sourceBottom - destinationBottom,
            accuracy: 0.001
        )

        let sourceTop = metrics.headerHeight
            + metrics.headerBottomSpacing
            + metrics.stackHeight
            + metrics.passTopSpacing
        let destinationTop = metrics.headerHeight + metrics.detailTopSpacing
        XCTAssertEqual(
            engine.passDetailTopInitialOffset(browserScrollOffset: 0),
            sourceTop - destinationTop,
            accuracy: 0.001
        )
    }

    func testCardsNeverCrossAboveExpandedPassFinalPosition() {
        let metrics = WalletMetrics(viewport: CGSize(width: 402, height: 874), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)
        let passFinalMinY = metrics.headerHeight + metrics.detailTopSpacing

        for index in 0..<4 {
            let sourceMinY = metrics.headerHeight
                + metrics.headerBottomSpacing
                + CGFloat(index) * metrics.cardOverlap
            let offset = engine.passSelectionOffset(
                cardIndex: index,
                progress: 1,
                browserScrollOffset: 0
            )
            XCTAssertGreaterThanOrEqual(sourceMinY + offset, passFinalMinY)
        }
    }

    func testPullDownStretchSpacingIsImmediateAndRubberBanded() {
        let metrics = WalletMetrics(viewport: CGSize(width: 390, height: 844), cardCount: 4)
        let engine = WalletLayoutEngine(metrics: metrics)

        XCTAssertEqual(engine.pullDownStretchSpacing(overscroll: 0), 0)
        XCTAssertGreaterThan(engine.pullDownStretchSpacing(overscroll: 1), 0)
        XCTAssertGreaterThan(
            engine.pullDownStretchSpacing(overscroll: 120),
            engine.pullDownStretchSpacing(overscroll: 30)
        )
        XCTAssertLessThan(engine.pullDownStretchSpacing(overscroll: 1_000), 38)
    }

    func testRubberBandPreservesDirectionAndCompressesDistance() {
        let engine = WalletLayoutEngine(metrics: WalletMetrics(viewport: CGSize(width: 390, height: 844)))
        let positive = engine.rubberBand(400, dimension: 844)
        let negative = engine.rubberBand(-400, dimension: 844)

        XCTAssertGreaterThan(positive, 0)
        XCTAssertLessThan(positive, 400)
        XCTAssertEqual(negative, -positive, accuracy: 0.001)
    }
}

// These tests cover the controller's async handoffs and reorder state.
@MainActor
final class WalletMotionControllerTests: XCTestCase {
    func testSelectingAndDismissingCardUsesTwoPhaseHandoff() async throws {
        let controller = WalletMotionController()
        let item = WalletItem.card(WalletSampleData.cards[0])

        controller.select(item, reduceMotion: true)
        XCTAssertEqual(controller.presentation, .cardDetail(item.id))
        XCTAssertEqual(controller.transitionProgress, 0)

        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(controller.transitionProgress, 1)

        controller.dismissDetail(reduceMotion: true)
        XCTAssertTrue(controller.isDismissing)
        XCTAssertEqual(controller.presentation, .cardDetail(item.id))

        try await Task.sleep(for: .milliseconds(240))
        XCTAssertEqual(controller.presentation, .browsing)
        XCTAssertFalse(controller.isDismissing)
    }

    func testReorderUpdatesModelAndReturnsToBrowsing() {
        let controller = WalletMotionController()
        var cards = WalletSampleData.cards
        let firstID = cards[0].id

        controller.beginReorder(cardID: firstID, index: 0)
        controller.updateReorder(translation: 165, destinationIndex: 3)
        controller.finishReorder(cards: &cards)

        XCTAssertEqual(cards[3].id, firstID)
        XCTAssertEqual(controller.presentation, .browsing)
        XCTAssertFalse(controller.isReordering)
    }

    func testDeterministicProgressClamps() {
        let controller = WalletMotionController()
        controller.setDeterministicProgress(-1)
        XCTAssertEqual(controller.transitionProgress, 0)
        controller.setDeterministicProgress(2)
        XCTAssertEqual(controller.transitionProgress, 1)
    }

    func testAddSheetUsesPreparationStateBeforePresentation() async throws {
        let controller = WalletMotionController()

        controller.presentAddSheet()
        XCTAssertEqual(controller.presentation, .preparingAddSheet)
        XCTAssertTrue(controller.isPreparingAddSheet)

        try await Task.sleep(for: .milliseconds(620))
        XCTAssertEqual(controller.presentation, .addSheet)
        XCTAssertFalse(controller.isPreparingAddSheet)
    }
}
