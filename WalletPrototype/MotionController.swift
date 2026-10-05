// MotionController.swift
// Owns presentation state, spring progress, reordering, dismissal, and haptics.

import SwiftUI
import UIKit

// One controller keeps every gesture and transition working from the same state.
@MainActor
final class WalletMotionController: ObservableObject {
    @Published private(set) var presentation: WalletPresentationState = .browsing
    @Published var detailDrag: CGFloat = 0
    @Published var transitionProgress: CGFloat = 0
    @Published private(set) var isDismissing = false
    @Published private(set) var reorderSourceIndex: Int?
    @Published private(set) var reorderDestinationIndex: Int?
    @Published var reorderTranslation: CGFloat = 0

    private let haptics = WalletHaptics()
    private var selectionTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var addSheetTask: Task<Void, Never>?

    var isReordering: Bool { reorderSourceIndex != nil }
    var isPreparingAddSheet: Bool { presentation == .preparingAddSheet }

    // MARK: - Selection

    func select(_ item: WalletItem, reduceMotion: Bool) {
        selectionTask?.cancel()
        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = false
        detailDrag = 0
        transitionProgress = 0
        let target: WalletPresentationState
        switch item {
        case .card: target = .cardDetail(item.id)
        case .pass: target = .passDetail(item.id)
        }
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(duration: 0.44, bounce: 0.18)

        // Mounting the detail at progress zero keeps the layer handoff invisible.
        presentation = target

        selectionTask = Task { [weak self] in
            // One frame gives SwiftUI time to commit the starting hierarchy.
            try? await Task.sleep(for: .milliseconds(18))
            guard !Task.isCancelled, let self, self.presentation == target else { return }
            withAnimation(animation) {
                self.transitionProgress = 1
            }
            self.selectionTask = nil
        }
        haptics.selection()
    }

    func dismissDetail(reduceMotion: Bool) {
        guard !isDismissing else { return }

        selectionTask?.cancel()
        selectionTask = nil
        dismissalTask?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.42, bounce: 0.16)) {
            // The detail stays mounted until the reverse spring finishes.
            isDismissing = true
            detailDrag = 0
            transitionProgress = 0
        }

        let settleDelay = reduceMotion ? Duration.milliseconds(190) : .milliseconds(500)
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self else { return }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.presentation = .browsing
                self.isDismissing = false
            }
            self.dismissalTask = nil
        }
    }

    // MARK: - Interactive Dismissal

    func updateDetailDrag(_ translation: CGFloat, viewportHeight: CGFloat) {
        let engine = WalletLayoutEngine(metrics: WalletMetrics(viewport: CGSize(width: 390, height: viewportHeight)))
        detailDrag = translation >= 0 ? engine.rubberBand(translation, dimension: viewportHeight) : translation * 0.18
        transitionProgress = max(0, min(1, 1 - max(translation, 0) / max(viewportHeight * 0.42, 1)))
    }

    func finishDetailDrag(translation: CGFloat, predictedTranslation: CGFloat, viewportHeight: CGFloat, reduceMotion: Bool) {
        let shouldDismiss = translation > viewportHeight * 0.15 || predictedTranslation > viewportHeight * 0.28
        if shouldDismiss {
            dismissDetail(reduceMotion: reduceMotion)
        } else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.5, bounce: 0.24)) {
                detailDrag = 0
                transitionProgress = 1
            }
        }
    }

    // MARK: - Reordering

    func beginReorder(cardID: String, index: Int) {
        guard reorderSourceIndex == nil else { return }
        reorderSourceIndex = index
        reorderDestinationIndex = index
        reorderTranslation = 0
        presentation = .reordering(cardID)
        haptics.lift()
    }

    func updateReorder(translation: CGFloat, destinationIndex: Int) {
        reorderTranslation = translation
        if destinationIndex != reorderDestinationIndex {
            reorderDestinationIndex = destinationIndex
            haptics.selection()
        }
    }

    func finishReorder(cards: inout [WalletCardModel]) {
        guard let source = reorderSourceIndex,
              let destination = reorderDestinationIndex,
              cards.indices.contains(source),
              cards.indices.contains(destination) else {
            cancelReorder()
            return
        }

        if source != destination {
            let card = cards.remove(at: source)
            cards.insert(card, at: destination)
        }

        withAnimation(.spring(duration: 0.42, bounce: 0.14)) {
            reorderSourceIndex = nil
            reorderDestinationIndex = nil
            reorderTranslation = 0
            presentation = .browsing
        }
        haptics.drop()
    }

    func cancelReorder() {
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
            reorderSourceIndex = nil
            reorderDestinationIndex = nil
            reorderTranslation = 0
            presentation = .browsing
        }
    }

    // MARK: - Add Sheet

    func presentAddSheet() {
        guard presentation == .browsing else { return }
        addSheetTask?.cancel()
        presentation = .preparingAddSheet
        haptics.selection()

        // The short preparation beat matches the Plus control's loading moment.
        addSheetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled, let self,
                  self.presentation == .preparingAddSheet else { return }
            self.presentation = .addSheet
            self.addSheetTask = nil
        }
    }

    func dismissTransientSurface() {
        addSheetTask?.cancel()
        addSheetTask = nil
        presentation = .browsing
    }

    // MARK: - Test Support

    func setDeterministicProgress(_ progress: CGFloat) {
        transitionProgress = min(max(progress, 0), 1)
    }
}

// Small, prepared generators keep feedback crisp during quick gesture changes.
@MainActor
private final class WalletHaptics {
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let liftGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let dropGenerator = UIImpactFeedbackGenerator(style: .soft)

    func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    func lift() {
        liftGenerator.prepare()
        liftGenerator.impactOccurred(intensity: 0.78)
    }

    func drop() {
        dropGenerator.prepare()
        dropGenerator.impactOccurred(intensity: 0.7)
    }
}
