// WalletShell.swift
// Builds the main Wallet screen and connects its stack, header, details, and gestures.

import SwiftUI
import UIKit

// WalletShell is the reusable visual container for this whole experiment.
struct WalletShell<DetailContent: View>: View {
    let items: [WalletItem]
    @ObservedObject var motion: WalletMotionController
    private let detailContent: (WalletItem) -> DetailContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cards: [WalletCardModel]
    @State private var browserScrollOffset: CGFloat = 0
    @State private var browserPullDistance: CGFloat = 0
    @State private var startupProgress: CGFloat
    @State private var startupHeaderProgress: CGFloat
    @State private var startupAnimationComplete: Bool
    @State private var hasStartedStartupAnimation = false
    private let startupAnimationEnabled: Bool
    private let pass: WalletPassModel

    init(
        items: [WalletItem],
        motion: WalletMotionController,
        @ViewBuilder detailContent: @escaping (WalletItem) -> DetailContent
    ) {
        self.items = items
        self.motion = motion
        self.detailContent = detailContent
        let startupAnimationEnabled = !ProcessInfo.processInfo.arguments.contains(
            "-DisableWalletStartupAnimation"
        )
        self.startupAnimationEnabled = startupAnimationEnabled
        _startupProgress = State(initialValue: startupAnimationEnabled ? 0 : 1)
        _startupHeaderProgress = State(initialValue: startupAnimationEnabled ? 0 : 1)
        _startupAnimationComplete = State(initialValue: !startupAnimationEnabled)
        _cards = State(initialValue: items.compactMap {
            guard case .card(let card) = $0 else { return nil }
            return card
        })
        let passes: [WalletPassModel] = items.compactMap { item -> WalletPassModel? in
            guard case .pass(let pass) = item else { return nil }
            return pass
        }
        pass = passes.first ?? WalletSampleData.pass
    }

    // MARK: - Root Composition

    var body: some View {
        GeometryReader { proxy in
            let metrics = WalletMetrics(
                viewport: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top,
                safeAreaBottom: proxy.safeAreaInsets.bottom,
                cardCount: cards.count
            )

            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                // The browser stays mounted so its cards can take part in detail transitions.
                browserView(metrics: metrics)
                    .allowsHitTesting(selectedItem == nil)
                    .accessibilityHidden(selectedItem != nil)
                    .zIndex(1)

                if let selectedItem {
                    detailView(item: selectedItem, metrics: metrics)
                        .transition(.identity)
                        .zIndex(2)
                }

                // Foreground copies preserve the stack's layer order while cards peel away.
                foregroundTransitionCards(metrics: metrics)
                    .zIndex(3)

                persistentHeader(item: selectedItem, metrics: metrics)
                    .opacity(startupHeaderProgress)
                    .blur(radius: reduceMotion ? 0 : 5 * (1 - startupHeaderProgress))
                    .animation(.easeOut(duration: 0.28).delay(0.025), value: startupHeaderProgress)
                    .zIndex(300)
            }
        }
        .sheet(isPresented: addSheetBinding) {
            AddToWalletSheet {
                motion.dismissTransientSurface()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(38)
            .presentationBackground(Color.white)
        }
        .onChange(of: cards) { _, _ in
            // Card order lives only for this launch.
        }
        .task {
            await runStartupAnimationIfNeeded()
        }
    }

    // MARK: - Presentation State

    private var selectedItem: WalletItem? {
        switch motion.presentation {
        case .cardDetail(let id):
            return cards.first(where: { $0.id == id }).map(WalletItem.card)
        case .passDetail(let id) where id == pass.id:
            return .pass(pass)
        default:
            return nil
        }
    }

    private var addSheetBinding: Binding<Bool> {
        Binding(
            get: { motion.presentation == .addSheet },
            set: { isPresented in
                if !isPresented { motion.dismissTransientSurface() }
            }
        )
    }

    // MARK: - Browsing Stack

    private func browserView(metrics: WalletMetrics) -> some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // This spacer reserves the fixed header while letting cards scroll behind it.
                    Color.clear
                        .frame(height: metrics.headerHeight + metrics.headerBottomSpacing)

                    cardStack(metrics: metrics)
                        .frame(height: metrics.stackHeight)

                    Group {
                        if selectedItem?.id == pass.id {
                            Color.clear
                        } else {
                            WalletPassView(pass: pass, expanded: false)
                        }
                    }
                    .frame(width: metrics.cardWidth, height: metrics.passHeight)
                    .offset(
                        y: passSelectionOffset(metrics: metrics)
                            + pullDownPassOffset(metrics: metrics)
                            + startupPassOffset(metrics: metrics)
                    )
                    .opacity(stackItemOpacity(itemID: pass.id))
                    .blur(radius: stackItemBlur(itemID: pass.id))
                    .animation(stackTransitionAnimation, value: motion.transitionProgress)
                    .animation(startupAnimation, value: startupProgress)
                    .padding(.top, metrics.passTopSpacing)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture {
                        guard startupAnimationComplete, !motion.isReordering else { return }
                        motion.select(.pass(pass), reduceMotion: reduceMotion)
                    }
                    .accessibilityAddTraits(.isButton)

                    Spacer(minLength: metrics.safeAreaBottom + 24)
                }
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "wallet-scroll")
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, rawOffset in
                browserScrollOffset = max(0, rawOffset)
                browserPullDistance = max(0, -rawOffset)
            }

        }
        .background(Color.clear)
    }

    private var walletTitleScrollProgress: CGFloat {
        // An eight-point ramp makes the title react to even a small scroll.
        min(max(browserScrollOffset / 8, 0), 1)
    }

    // MARK: - Header

    private func persistentHeader(item: WalletItem?, metrics: WalletMetrics) -> some View {
        let detailProgress = item == nil ? CGFloat.zero : motion.transitionProgress
        let titleTransitionProgress = max(walletTitleScrollProgress, detailProgress)

        return HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .leading) {
                Text("Wallet")
                    .font(.largeTitle.weight(.bold))
                    .opacity(1 - titleTransitionProgress)
                    .blur(radius: reduceMotion ? 0 : 6 * titleTransitionProgress)
                    .accessibilityLabel(item == nil && titleTransitionProgress < 0.98 ? "Wallet" : "")
                    .accessibilityHidden(item != nil || titleTransitionProgress >= 0.98)

                if item != nil {
                    GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close") {
                        motion.dismissDetail(reduceMotion: reduceMotion)
                    }
                    .opacity(detailProgress)
                    .scaleEffect(0.88 + detailProgress * 0.12)
                    .allowsHitTesting(!motion.isDismissing)
                    .accessibilityHidden(motion.isDismissing)
                }
            }

            Spacer(minLength: 12)

            ZStack {
                Button {
                    motion.presentAddSheet()
                } label: {
                    ZStack {
                        Image(systemName: "plus")
                            .font(.system(size: 27, weight: .regular))
                            .opacity(motion.isPreparingAddSheet ? 0 : 1)

                        ProgressView()
                            .controlSize(.regular)
                            .tint(.secondary)
                            .opacity(motion.isPreparingAddSheet ? 1 : 0)
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                    .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                .opacity(1 - detailProgress)
                .allowsHitTesting(item == nil)
                .accessibilityHidden(item != nil)
                .animation(.easeInOut(duration: 0.16), value: motion.isPreparingAddSheet)

                if case .pass = item {
                    GlassCircleButton(systemName: "square.and.arrow.up", accessibilityLabel: "Share") { }
                        .opacity(detailProgress)
                        .scaleEffect(0.88 + detailProgress * 0.12)
                        .allowsHitTesting(!motion.isDismissing)
                }
            }

            overflowMenu(item: item)
        }
        .frame(height: metrics.headerHeight)
        .padding(.horizontal, metrics.horizontalInset)
    }

    private func overflowMenu(item: WalletItem?) -> some View {
        Menu {
            if item != nil {
                Button(action: {}) { Label("Item Details", systemImage: "info.circle") }
                Button(action: {}) { Label("Notifications", systemImage: "bell") }
            } else {
                Button(action: {}) { Label("Orders", systemImage: "shippingbox") }
                Button(action: {}) { Label("Preauthorized Payments", systemImage: "dollarsign.arrow.circlepath") }
                Divider()
                Button(action: {}) { Label("AutoFill", systemImage: "rectangle.and.pencil.and.ellipsis") }
                Button(action: {}) { Label("Expired", systemImage: "clock.badge.exclamationmark") }
                Divider()
                Button(action: {}) { Label("Notifications", systemImage: "bell") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .id("wallet-overflow-control")
        .accessibilityLabel("More")
    }

    // MARK: - Card Stack

    private func cardStack(metrics: WalletMetrics) -> some View {
        let engine = WalletLayoutEngine(metrics: metrics)

        return ZStack(alignment: .top) {
            // Artwork is separate from hit regions so every visible card strip stays tappable.
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let source = motion.reorderSourceIndex
                let destination = motion.reorderDestinationIndex ?? source
                let isLifted = source == index
                let displacement: CGFloat = {
                    guard let source, let destination else { return 0 }
                    return engine.displacedOffset(index: index, sourceIndex: source, destinationIndex: destination)
                }()

                Group {
                    if selectedItem?.id == card.id
                        || isForegroundTransitionCard(index: index) {
                        Color.clear
                    } else {
                        PaymentCardView(card: card)
                    }
                }
                    .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                    .scaleEffect(isLifted ? 1.035 : cardSelectionScale(index: index))
                    .offset(
                        y: CGFloat(index) * metrics.cardOverlap
                            + displacement
                            + (isLifted ? motion.reorderTranslation : 0)
                            + pullDownCardOffset(index: index, metrics: metrics)
                            + cardSelectionOffset(index: index, metrics: metrics)
                            + startupCardOffset(index: index, metrics: metrics)
                    )
                    .opacity(stackItemOpacity(itemID: card.id))
                    .blur(radius: stackItemBlur(itemID: card.id))
                    .shadow(color: .black.opacity(isLifted ? 0.28 : 0), radius: isLifted ? 24 : 0, y: isLifted ? 16 : 0)
                    .zIndex(isLifted ? 100 : Double(index))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(.spring(duration: 0.34, bounce: 0.12), value: displacement)
                    .animation(stackTransitionAnimation, value: motion.transitionProgress)
                    .animation(startupAnimation, value: startupProgress)
            }

            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let source = motion.reorderSourceIndex
                let destination = motion.reorderDestinationIndex ?? source
                let isLifted = source == index
                let displacement: CGFloat = {
                    guard let source, let destination else { return 0 }
                    return engine.displacedOffset(index: index, sourceIndex: source, destinationIndex: destination)
                }()
                let exposedHeight = index == cards.count - 1 ? metrics.cardHeight : metrics.cardOverlap

                Color.clear
                    .frame(width: metrics.cardWidth, height: exposedHeight)
                    .contentShape(Rectangle())
                    .overlay {
                        ReorderGestureBridge(
                            onTap: {
                                guard startupAnimationComplete, !motion.isReordering else { return }
                                motion.select(.card(card), reduceMotion: reduceMotion)
                            },
                            onBegan: {
                                guard startupAnimationComplete else { return }
                                motion.beginReorder(cardID: card.id, index: index)
                            },
                            onChanged: { translation in
                                guard motion.reorderSourceIndex == index else { return }
                                let destination = engine.reorderIndex(
                                    currentIndex: index,
                                    translation: translation,
                                    cardCount: cards.count
                                )
                                motion.updateReorder(translation: translation, destinationIndex: destination)
                            },
                            onEnded: {
                                guard motion.reorderSourceIndex == index else { return }
                                motion.finishReorder(cards: &cards)
                            },
                            onCancelled: {
                                guard motion.reorderSourceIndex == index else { return }
                                motion.cancelReorder()
                            }
                        )
                    }
                    .offset(
                        y: CGFloat(index) * metrics.cardOverlap
                            + displacement
                            + (isLifted ? motion.reorderTranslation : 0)
                            + pullDownCardOffset(index: index, metrics: metrics)
                            + startupCardOffset(index: index, metrics: metrics)
                    )
                    .zIndex(isLifted ? 201 : 110 + Double(index))
                    .animation(.spring(duration: 0.34, bounce: 0.12), value: displacement)
                    .animation(startupAnimation, value: startupProgress)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("wallet-card-\(card.id)")
                    .accessibilityLabel(card.accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double tap to open. Touch and hold to reorder.")
            }
        }
        .frame(width: metrics.viewport.width, height: metrics.stackHeight, alignment: .top)
    }

    // MARK: - Startup Motion

    private var stackTransitionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(duration: 0.44, bounce: 0.18)
    }

    private var startupAnimation: Animation {
        // Separate travel distances make the startup pile fan into place.
        .spring(duration: 0.50, bounce: 0.14)
    }

    private func startupCardOffset(index: Int, metrics: WalletMetrics) -> CGFloat {
        WalletLayoutEngine(metrics: metrics).startupCardOffset(index: index)
            * (1 - startupProgress)
    }

    private func startupPassOffset(metrics: WalletMetrics) -> CGFloat {
        WalletLayoutEngine(metrics: metrics).startupPassOffset()
            * (1 - startupProgress)
    }

    @MainActor
    private func runStartupAnimationIfNeeded() async {
        guard !hasStartedStartupAnimation else { return }
        hasStartedStartupAnimation = true

        guard startupAnimationEnabled, !reduceMotion else {
            startupProgress = 1
            startupHeaderProgress = 1
            startupAnimationComplete = true
            return
        }

        // One empty frame gives the app launch and our springs a clean handoff.
        await Task.yield()
        startupHeaderProgress = 1
        startupProgress = 1

        try? await Task.sleep(for: .milliseconds(560))
        guard !Task.isCancelled else { return }
        startupAnimationComplete = true
    }

    // MARK: - Stack Transition Helpers

    private func pullDownCardOffset(index: Int, metrics: WalletMetrics) -> CGFloat {
        WalletLayoutEngine(metrics: metrics).pullDownStretchSpacing(
            overscroll: browserPullDistance
        ) * CGFloat(index)
    }

    private func pullDownPassOffset(metrics: WalletMetrics) -> CGFloat {
        WalletLayoutEngine(metrics: metrics).pullDownStretchSpacing(
            overscroll: browserPullDistance
        ) * CGFloat(max(cards.count - 1, 0))
    }

    private func cardSelectionOffset(index: Int, metrics: WalletMetrics) -> CGFloat {
        guard let selectedItem else { return 0 }
        guard !reduceMotion else { return 0 }

        let progress = motion.transitionProgress
        switch selectedItem {
        case .pass:
            // Cards follow the pass upward but never cross its final top edge.
            return WalletLayoutEngine(metrics: metrics).passSelectionOffset(
                cardIndex: index,
                progress: progress,
                browserScrollOffset: browserScrollOffset
            )

        case .card(let selectedCard):
            guard let selectedIndex = cards.firstIndex(where: { $0.id == selectedCard.id }),
                  index != selectedIndex else { return 0 }

            return WalletLayoutEngine(metrics: metrics).selectionOffset(
                index: index,
                selectedIndex: selectedIndex,
                progress: progress,
                browserScrollOffset: browserScrollOffset
            )
        }
    }

    private func cardSelectionScale(index: Int) -> CGFloat {
        guard !reduceMotion,
              case .card(let selectedCard) = selectedItem,
              let selectedIndex = cards.firstIndex(where: { $0.id == selectedCard.id }),
              index != selectedIndex else { return 1 }

        let depth = index < selectedIndex ? CGFloat(0.035) : CGFloat(0.012)
        return 1 - depth * motion.transitionProgress
    }

    private func isForegroundTransitionCard(index: Int) -> Bool {
        guard !reduceMotion,
              case .card(let selectedCard) = selectedItem,
              let selectedIndex = cards.firstIndex(where: { $0.id == selectedCard.id }) else {
            return false
        }
        return index > selectedIndex
    }

    @ViewBuilder
    private func foregroundTransitionCards(metrics: WalletMetrics) -> some View {
        if !reduceMotion,
           case .card(let selectedCard) = selectedItem,
           let selectedIndex = cards.firstIndex(where: { $0.id == selectedCard.id }) {
            ZStack(alignment: .top) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > selectedIndex {
                        PaymentCardView(card: card)
                            .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                            .offset(
                                y: metrics.headerHeight
                                    + metrics.headerBottomSpacing
                                    + CGFloat(index) * metrics.cardOverlap
                                    - browserScrollOffset
                            )
                            .zIndex(Double(index))
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Flattening the foreground cards keeps their shared exit smooth.
            .compositingGroup()
            .offset(y: metrics.viewport.height * 0.42 * motion.transitionProgress)
            .opacity(foregroundStackOpacity)
            .blur(radius: foregroundStackBlur)
            .animation(stackTransitionAnimation, value: motion.transitionProgress)
            .allowsHitTesting(false)
        }
    }

    private var foregroundStackOpacity: CGFloat {
        1 - min(motion.transitionProgress * 1.35, 1)
    }

    private var foregroundStackBlur: CGFloat {
        let midpointEnvelope = 1 - abs((motion.transitionProgress * 2) - 1)
        return max(0, midpointEnvelope) * 3
    }

    private func passSelectionOffset(metrics: WalletMetrics) -> CGFloat {
        guard let selectedItem, selectedItem.id != pass.id else { return 0 }
        guard !reduceMotion else { return 0 }
        return metrics.viewport.height * 0.82 * motion.transitionProgress
    }

    private func stackItemOpacity(itemID: String) -> CGFloat {
        guard let selectedItem, selectedItem.id != itemID else { return 1 }
        // Unselected items finish fading just before their movement settles.
        return 1 - min(motion.transitionProgress * 1.35, 1)
    }

    private func stackItemBlur(itemID: String) -> CGFloat {
        guard !reduceMotion,
              let selectedItem,
              selectedItem.id != itemID else { return 0 }

        // A midpoint blur softens movement while leaving both endpoints sharp.
        let midpointEnvelope = 1 - abs((motion.transitionProgress * 2) - 1)
        return max(0, midpointEnvelope) * 4
    }

    // MARK: - Detail Presentation

    private func detailView(item: WalletItem, metrics: WalletMetrics) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // The spacer keeps details aligned beneath the persistent header.
                Color.clear
                    .frame(height: metrics.headerHeight)

                switch item {
                case .card(let card):
                    PaymentCardView(card: card)
                        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                        .padding(.top, metrics.detailTopSpacing)
                        .offset(y: detailItemTopOffset(item: item, metrics: metrics))
                        .opacity(reduceMotion ? detailChromeProgress : 1)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            motion.dismissDetail(reduceMotion: reduceMotion)
                        }
                        .simultaneousGesture(detailDismissGesture(metrics: metrics))

                case .pass(let pass):
                    ZStack(alignment: .top) {
                        WalletPassView(pass: pass, expanded: true)
                            .frame(
                                width: metrics.cardWidth,
                                height: interpolatedPassHeight(metrics: metrics)
                            )
                            .offset(y: detailItemTopOffset(item: item, metrics: metrics))
                            .opacity(reduceMotion ? detailChromeProgress : 1)
                    }
                        .frame(width: metrics.cardWidth, height: metrics.detailPassHeight, alignment: .top)
                        .padding(.top, metrics.detailTopSpacing)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            motion.dismissDetail(reduceMotion: reduceMotion)
                        }
                        .simultaneousGesture(detailDismissGesture(metrics: metrics))
                }

                detailContent(item)
                    .padding(.horizontal, metrics.horizontalInset)
                    .padding(.top, 22)
                    .padding(.bottom, metrics.safeAreaBottom + 30)
                    .opacity(detailChromeOpacity)
                    .blur(radius: detailChromeBlur)
                    .scaleEffect(0.972 + 0.028 * detailChromeProgress, anchor: .top)
                    .offset(y: detailChromeTravel(item: item, metrics: metrics) * (1 - detailChromeProgress))
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .offset(y: motion.detailDrag)
        .allowsHitTesting(!motion.isDismissing)
    }

    private var detailChromeOpacity: CGFloat {
        detailChromeProgress
    }

    private var detailChromeProgress: CGFloat {
        // Detail content begins moving in the same frame as its item.
        min(max(motion.transitionProgress, 0), 1)
    }

    private var detailChromeBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        // The content sharpens as it catches up with the selected item.
        return 5.5 * (1 - detailChromeProgress)
    }

    private func detailChromeTravel(item: WalletItem, metrics: WalletMetrics) -> CGFloat {
        guard !reduceMotion else { return 0 }

        let engine = WalletLayoutEngine(metrics: metrics)

        switch item {
        case .card(let card):
            guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return 0 }
            return engine.cardDetailContentInitialOffset(
                index: index,
                browserScrollOffset: browserScrollOffset
            )
        case .pass:
            return engine.passDetailContentInitialOffset(
                browserScrollOffset: browserScrollOffset
            )
        }
    }

    private func detailItemTopOffset(item: WalletItem, metrics: WalletMetrics) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let engine = WalletLayoutEngine(metrics: metrics)
        let initialOffset: CGFloat

        switch item {
        case .card(let card):
            guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return 0 }
            initialOffset = engine.cardDetailTopInitialOffset(
                index: index,
                browserScrollOffset: browserScrollOffset
            )
        case .pass:
            initialOffset = engine.passDetailTopInitialOffset(
                browserScrollOffset: browserScrollOffset
            )
        }

        return initialOffset * (1 - detailChromeProgress)
    }

    private func interpolatedPassHeight(metrics: WalletMetrics) -> CGFloat {
        guard !reduceMotion else { return metrics.detailPassHeight }
        return metrics.passHeight
            + (metrics.detailPassHeight - metrics.passHeight) * detailChromeProgress
    }

    private func detailDismissGesture(metrics: WalletMetrics) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                motion.updateDetailDrag(value.translation.height, viewportHeight: metrics.viewport.height)
            }
            .onEnded { value in
                motion.finishDetailDrag(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    viewportHeight: metrics.viewport.height,
                    reduceMotion: reduceMotion
                )
            }
    }
}

// MARK: - UIKit Gesture Bridge

// UIKit recognizers give taps, long presses, and scroll pans clear ownership.
private struct ReorderGestureBridge: UIViewRepresentable {
    var onTap: () -> Void
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    var onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        recognizer.minimumPressDuration = 0.42
        recognizer.allowableMovement = 14
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(tapRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void
        var onCancelled: () -> Void
        private var initialY: CGFloat = 0

        init(
            onTap: @escaping () -> Void,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTap()
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let currentY = recognizer.location(in: view.window).y

            switch recognizer.state {
            case .began:
                initialY = currentY
                onBegan()
            case .changed:
                onChanged(currentY - initialY)
            case .ended:
                onEnded()
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Scroll pans must win immediately so the rubber-band can always finish.
            !(gestureRecognizer is UIPanGestureRecognizer)
                && !(otherGestureRecognizer is UIPanGestureRecognizer)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UILongPressGestureRecognizer else { return true }

            // Reordering waits until the enclosing scroll view is fully at rest.
            var ancestor = gestureRecognizer.view?.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    return !scrollView.isDragging && !scrollView.isDecelerating
                }
                ancestor = current.superview
            }
            return true
        }
    }
}

// MARK: - Shared Controls

// This keeps the circular glass controls visually consistent across header states.
private struct GlassCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: systemName == "plus" ? 27 : 23, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
