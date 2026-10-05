// WalletPrototypeApp.swift
// Starts the app and connects the sample data, motion controller, and detail views.

import SwiftUI

@main
struct WalletPrototypeApp: App {
    @StateObject private var motion = WalletMotionController()

    var body: some Scene {
        WindowGroup {
            WalletShell(items: WalletSampleData.items, motion: motion) { item in
                WalletSampleDetail(item: item)
            }
            .preferredColorScheme(.light)
        }
    }
}
