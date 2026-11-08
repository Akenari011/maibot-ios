//
//  MaiBotApp.swift
//  MaiBot
//

import SwiftUI

@main
struct MaiBotApp: App {
    @State private var client = APIClient()
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                .environment(auth)
                .environment(\.palette, .panel)
                .tint(Palette.panel.orange)
                .preferredColorScheme(.light)
                .task { await auth.restore(client: client) }
        }
    }
}