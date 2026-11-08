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
            ThemedRoot()
                .environment(client)
                .environment(auth)
                .task { await auth.restore(client: client) }
        }
    }
}