// CardArtwork.swift
// Draws the simple card and pass surfaces used throughout the Wallet shell.

import SwiftUI

// The card stays intentionally blank so motion and layering remain the focus.
struct PaymentCardView: View {
    let card: WalletCardModel

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(card.solidColor)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.black.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("wallet-card-\(card.id)")
            .accessibilityLabel(card.accessibilityLabel)
    }
}

// The pass uses the same shape treatment with its own taller layout in the shell.
struct WalletPassView: View {
    let pass: WalletPassModel
    let expanded: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: 0xE3A93A))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.black.opacity(0.11), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.13), radius: 10, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("wallet-pass-\(pass.id)")
            .accessibilityLabel(pass.accessibilityLabel)
    }
}

// These colors make each layer easy to follow while tuning animations.
private extension WalletCardModel {
    var solidColor: Color {
        switch artwork {
        case .aurora: Color(hex: 0x3975D7)
        case .evergreen: Color(hex: 0x4C9B68)
        case .signal: Color(hex: 0xDD554D)
        case .halo: Color(hex: 0x1C1C1E)
        }
    }
}

// A tiny hex helper keeps the sample palette readable in code.
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
