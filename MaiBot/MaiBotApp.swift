//
//  MaiBotApp.swift
//  MaiBot
//

import SwiftUI

@main
struct MaiBotApp: App {
    @State private var client = APIClient()
    @State private var auth = AuthStore()
    @AppStorage("maibot.theme") private var themeRaw = ThemePreference.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var preference: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .system
    }

    private var palette: Palette {
        switch preference {
        case .midnight: return .midnight
        case .paper:    return .paper
        case .system:   return systemScheme == .dark ? .midnight : .paper
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                .environment(auth)
                .environment(\.palette, palette)
                .tint(palette.accent)
                .preferredColorScheme(preference == .system ? nil : (preference == .midnight ? .dark : .light))
                .task {
                    await auth.restore(client: client)
                }
        }
    }
}
