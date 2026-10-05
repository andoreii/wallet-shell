// Layout.swift
// Holds the responsive measurements and geometry math for every Wallet transition.

import CoreGraphics

// WalletMetrics turns the current screen size into one consistent set of dimensions.
struct WalletMetrics: Equatable, Sendable {
    let viewport: CGSize
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let horizontalInset: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardOverlap: CGFloat
    let stackHeight: CGFloat
    let headerHeight: CGFloat
    let headerBottomSpacing: CGFloat
    let passTopSpacing: CGFloat
    let passHeight: CGFloat
    let detailPassHeight: CGFloat
    let detailTopSpacing: CGFloat
    let controlDiameter: CGFloat

    init(viewport: CGSize, safeAreaTop: CGFloat = 0, safeAreaBottom: CGFloat = 0, cardCount: Int = 4) {
        self.viewport = viewport
        self.safeAreaTop = safeAreaTop
        self.safeAreaBottom = safeAreaBottom

        // Measurements interpolate between the iPhone 14 and iPhone 17 Pro references.
        let widthProgress = min(max((viewport.width - 390) / 12, 0), 1)
        horizontalInset = 20 - (4 * widthProgress)
        cardWidth = viewport.width - (horizontalInset * 2)
        cardHeight = cardWidth / 1.59
        cardOverlap = 55 + widthProgress
        stackHeight = cardHeight + cardOverlap * CGFloat(max(cardCount - 1, 0))
        headerHeight = 52
        headerBottomSpacing = 16
        passTopSpacing = 38
        passHeight = min(430 + (10 * widthProgress), viewport.height * 0.54)
        detailPassHeight = min(550, viewport.height * 0.64)
        // Expanded items settle a little closer to the header than the stack does.
        detailTopSpacing = 6
        controlDiameter = 52
    }
}

// WalletLayoutEngine keeps animation paths testable and separate from SwiftUI views.
struct WalletLayoutEngine: Sendable {
    let metrics: WalletMetrics

    private var startupOriginY: CGFloat {
        // A shared off-screen origin lets the startup pile fan into separate slots.
        metrics.viewport.height + 8
    }

    func collapsedCardFrame(index: Int) -> CGRect {
        CGRect(
            x: metrics.horizontalInset,
            y: CGFloat(index) * metrics.cardOverlap,
            width: metrics.cardWidth,
            height: metrics.cardHeight
        )
    }

    func startupCardOffset(index: Int) -> CGFloat {
        let restingY = metrics.headerHeight
            + metrics.headerBottomSpacing
            + CGFloat(index) * metrics.cardOverlap
        return max(0, startupOriginY - restingY)
    }

    func startupPassOffset() -> CGFloat {
        let restingY = metrics.headerHeight
            + metrics.headerBottomSpacing
            + metrics.stackHeight
            + metrics.passTopSpacing
        return max(0, startupOriginY - restingY)
    }

    func reorderIndex(currentIndex: Int, translation: CGFloat, cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        let raw = CGFloat(currentIndex) + translation / metrics.cardOverlap
        return min(max(Int(raw.rounded()), 0), cardCount - 1)
    }

    func displacedOffset(index: Int, sourceIndex: Int, destinationIndex: Int) -> CGFloat {
        guard sourceIndex != destinationIndex else { return 0 }
        if sourceIndex < destinationIndex, index > sourceIndex, index <= destinationIndex {
            return -metrics.cardOverlap
        }
        if sourceIndex > destinationIndex, index >= destinationIndex, index < sourceIndex {
            return metrics.cardOverlap
        }
        return 0
    }

    func selectedCardTravel(index: Int, browserScrollOffset: CGFloat) -> CGFloat {
        // This is the exact trip from a card's stack slot to its detail position.
        metrics.detailTopSpacing
            - metrics.headerBottomSpacing
            - CGFloat(index) * metrics.cardOverlap
            + browserScrollOffset
    }

    func cardDetailContentInitialOffset(index: Int, browserScrollOffset: CGFloat) -> CGFloat {
        // Detail content starts on the same path as its selected card.
        -selectedCardTravel(index: index, browserScrollOffset: browserScrollOffset)
    }

    func cardDetailTopInitialOffset(index: Int, browserScrollOffset: CGFloat) -> CGFloat {
        -selectedCardTravel(index: index, browserScrollOffset: browserScrollOffset)
    }

    func passDetailTopInitialOffset(browserScrollOffset: CGFloat) -> CGFloat {
        let sourceTop = metrics.headerHeight
            + metrics.headerBottomSpacing
            + metrics.stackHeight
            + metrics.passTopSpacing
            - browserScrollOffset
        let destinationTop = metrics.headerHeight + metrics.detailTopSpacing
        return sourceTop - destinationTop
    }

    func passDetailContentInitialOffset(browserScrollOffset: CGFloat) -> CGFloat {
        // Pass content follows the bottom edge because the pass grows while moving.
        let sourceTop = metrics.headerHeight
            + metrics.detailTopSpacing
            + passDetailTopInitialOffset(browserScrollOffset: browserScrollOffset)
        let sourceBottom = sourceTop + metrics.passHeight
        let destinationBottom = metrics.headerHeight
            + metrics.detailTopSpacing
            + metrics.detailPassHeight
        return sourceBottom - destinationBottom
    }

    func passSelectionOffset(
        cardIndex: Int,
        progress: CGFloat,
        browserScrollOffset: CGFloat
    ) -> CGFloat {
        let cardSourceMinY = metrics.headerHeight
            + metrics.headerBottomSpacing
            + CGFloat(cardIndex) * metrics.cardOverlap
            - browserScrollOffset
        let passFinalMinY = metrics.headerHeight + metrics.detailTopSpacing

        // Scrolled cards never get pulled back down or cross above the expanded pass.
        guard cardSourceMinY >= passFinalMinY else { return 0 }

        let passTravel = -passDetailTopInitialOffset(
            browserScrollOffset: browserScrollOffset
        )
        let proposedOffset = passTravel * 0.36 * progress
        let finalPositionFloor = passFinalMinY - cardSourceMinY
        return max(proposedOffset, finalPositionFloor)
    }

    func pullDownStretchSpacing(overscroll: CGFloat) -> CGFloat {
        guard overscroll > 0 else { return 0 }
        // Rubber-banding opens the stack quickly without letting the gaps run away.
        return rubberBand(overscroll, dimension: 90) * 0.42
    }

    func selectionOffset(
        index: Int,
        selectedIndex: Int,
        progress: CGFloat,
        browserScrollOffset: CGFloat
    ) -> CGFloat {
        guard index != selectedIndex else { return 0 }

        if index < selectedIndex {
            // Cards behind the selection follow it upward and stop at its final top edge.
            let proposedOffset = selectedCardTravel(
                index: selectedIndex,
                browserScrollOffset: browserScrollOffset
            ) * 0.36 * progress
            let collapsedGlobalMinY = metrics.headerHeight
                + metrics.headerBottomSpacing
                + CGFloat(index) * metrics.cardOverlap
                - browserScrollOffset
            let selectedFinalMinY = metrics.headerHeight + metrics.detailTopSpacing
            let finalPositionFloor = selectedFinalMinY - collapsedGlobalMinY
            return max(proposedOffset, finalPositionFloor)
        }

        // Cards in front peel downward while keeping their original layer order.
        return metrics.viewport.height * 0.42 * progress
    }

    func rubberBand(_ distance: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return 0 }
        let coefficient: CGFloat = 0.55
        let magnitude = abs(distance)
        let result = (coefficient * magnitude * dimension) / (dimension + coefficient * magnitude)
        return distance < 0 ? -result : result
    }
}
