//
//  RootView.swift
//  MaiBot
//

import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                ZStack {
                    p.background.ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}

// MARK: - Main shell

/// Named AppTab, not Tab: SwiftUI already declares a `Tab` type and shadowing
/// it makes Tab("title", systemImage:value:) unconstructable.
enum AppTab: Hashable {
    case overview, bots, logs, config, settings
}

struct MainTabView: View {
    @Environment(\.palette) private var p
    @State private var selection: AppTab = .overview

    var body: some View {
        TabView(selection: $selection) {
            Tab("概览", systemImage: "square.grid.2x2", value: AppTab.overview) {
                DashboardView()
            }
            Tab("机器人", systemImage: "cpu", value: AppTab.bots) {
                BotsView()
            }
            Tab("日志", systemImage: "text.alignleft", value: AppTab.logs) {
                LogsView()
            }
            Tab("配置", systemImage: "slider.horizontal.3", value: AppTab.config) {
                ConfigView()
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(p.accent)
    }
}
