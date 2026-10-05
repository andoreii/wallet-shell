// DetailViews.swift
// Provides replaceable sample details and the inert add-items sheet.

import SwiftUI

// This is placeholder content that travels with the selected card or pass.
struct WalletSampleDetail: View {
    let item: WalletItem

    var body: some View {
        switch item {
        case .card(let card):
            cardDetail(card)
        case .pass:
            passDetail
        }
    }

    private func cardDetail(_ card: WalletCardModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Overview")
                        .font(.system(size: 17, weight: .medium))
                    Text(card.name.capitalized)
                        .font(.system(size: 28, weight: .bold))
                }
                Spacer()
                Button("Open") { }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 21)
                    .frame(height: 44)
                    .background(.black, in: Capsule())
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text("Latest Activity")
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                activityRow(icon: "sparkles", title: "Welcome", subtitle: "Today", value: "+12")
                Divider().padding(.leading, 58)
                activityRow(icon: "location.fill", title: "Studio visit", subtitle: "Yesterday", value: "2 hr")
                Divider().padding(.leading, 58)
                activityRow(icon: "person.2.fill", title: "Community event", subtitle: "Friday", value: "+4")
            }
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var passDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pass Information")
                .font(.system(size: 22, weight: .bold))
            Text("This is a local demonstration pass. It contains no scannable code, account connection, or payment capability.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Label("Sample membership", systemImage: "person.crop.circle")
            Label("Always available", systemImage: "clock")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func activityRow(icon: String, title: String, subtitle: String, value: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.system(size: 16, weight: .medium))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// The add sheet mirrors Wallet's visual hierarchy without adding real actions.
struct AddToWalletSheet: View {
    let dismiss: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Add to Wallet")
                        .font(.system(size: 28, weight: .bold))

                    Text("Keep all the cards, keys, and passes you use every day all in one place.")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                .padding(.horizontal, 38)
                .padding(.top, 10)

                addSection {
                    addRow(
                        icon: "wallet.pass.fill",
                        iconColor: .black,
                        title: "Items Found For You",
                        subtitle: "From other devices",
                        loading: true,
                        height: 56
                    )
                }
                .padding(.top, 30)

                addSection {
                    addRow(icon: "creditcard.fill", iconColor: .cyan, title: "Card or Membership")
                    sectionDivider
                    addRow(icon: "tram.fill", iconColor: .green, title: "Transit Pass")
                    sectionDivider
                    addRow(icon: "person.text.rectangle.fill", iconColor: .orange, title: "Identity Card")
                }
                .padding(.top, 28)

                addSection {
                    addRow(icon: "star.fill", iconColor: .orange, title: "Rewards Membership")
                    sectionDivider
                    addRow(icon: "person.crop.circle.fill", iconColor: .blue, title: "Account Pass")
                    sectionDivider
                    addRow(icon: "calendar.badge.clock", iconColor: .purple, title: "Flexible Options")
                }
                .padding(.top, 28)
                .padding(.bottom, 42)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
    }

    private func addSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.leading, 52)
            .padding(.trailing, 16)
    }

    private func addRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        loading: Bool = false,
        height: CGFloat = 44
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if loading {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .contentShape(Rectangle())
    }
}
