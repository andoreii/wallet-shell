// Models.swift
// Defines the cards, pass, presentation states, and sample content used by the app.

import SwiftUI

// The artwork names also provide stable identities for the four card colors.
enum CardArtworkStyle: String, CaseIterable, Equatable, Sendable {
    case aurora
    case evergreen
    case signal
    case halo
}

// A card only carries the display and accessibility data the shell needs.
struct WalletCardModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let trailingText: String
    let footerText: String
    let accessibilityLabel: String
    let artwork: CardArtworkStyle
}

// The pass model stays neutral so this shell can be reused outside payments.
struct WalletPassModel: Identifiable, Equatable, Sendable {
    let id: String
    let organization: String
    let holderName: String
    let membershipLabel: String
    let membershipValue: String
    let validityLabel: String
    let validityValue: String
    let accessibilityLabel: String
}

// WalletItem lets cards and passes share one presentation pipeline.
enum WalletItem: Identifiable, Equatable, Sendable {
    case card(WalletCardModel)
    case pass(WalletPassModel)

    var id: String {
        switch self {
        case .card(let card): card.id
        case .pass(let pass): pass.id
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .card(let card): card.accessibilityLabel
        case .pass(let pass): pass.accessibilityLabel
        }
    }
}

// This state keeps every full-screen or transient presentation mutually exclusive.
enum WalletPresentationState: Equatable, Sendable {
    case browsing
    case cardDetail(String)
    case passDetail(String)
    case reordering(String)
    case preparingAddSheet
    case addSheet
    case overflowMenu

    var selectedItemID: String? {
        switch self {
        case .cardDetail(let id), .passDetail(let id), .reordering(let id): id
        case .browsing, .preparingAddSheet, .addSheet, .overflowMenu: nil
        }
    }
}

// Local sample data keeps the project self-contained and resets on each launch.
enum WalletSampleData {
    static let cards: [WalletCardModel] = [
        WalletCardModel(
            id: "aurora",
            name: "AURORA",
            subtitle: "CITY ACCESS",
            trailingText: "READY",
            footerText: "EXPRESS",
            accessibilityLabel: "Aurora city access card",
            artwork: .aurora
        ),
        WalletCardModel(
            id: "evergreen",
            name: "EVERGREEN",
            subtitle: "COLLECTIVE",
            trailingText: "MEMBER",
            footerText: "PLUS",
            accessibilityLabel: "Evergreen membership card",
            artwork: .evergreen
        ),
        WalletCardModel(
            id: "signal",
            name: "SIGNAL",
            subtitle: "CREATIVE CLUB",
            trailingText: "ACTIVE",
            footerText: "•••• 2048",
            accessibilityLabel: "Signal creative club card",
            artwork: .signal
        ),
        WalletCardModel(
            id: "halo",
            name: "HALO",
            subtitle: "STUDIO",
            trailingText: "12",
            footerText: "MEMBER SINCE 2026",
            accessibilityLabel: "Halo studio membership card",
            artwork: .halo
        )
    ]

    static let pass = WalletPassModel(
        id: "skylark-pass",
        organization: "SKYLARK",
        holderName: "SAMPLE MEMBER",
        membershipLabel: "MEMBERSHIP",
        membershipValue: "DEMO 1402",
        validityLabel: "VALID THROUGH",
        validityValue: "Always",
        accessibilityLabel: "Skylark sample membership pass"
    )

    static let items: [WalletItem] = cards.map(WalletItem.card) + [.pass(pass)]
}
