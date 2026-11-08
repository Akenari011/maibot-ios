//
//  RootView.swift
//  MaiBot
//

import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                ZStack { p.bg.ignoresSafeArea(); ProgressView().controlSize(.large) }
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainShell()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.state)
    }
}

enum AppTab: Hashable { case home, chat, manage }
enum HomeRoute: Hashable { case activity, models, settings }
enum ManageRoute: Hashable { case settings }

struct MainShell: View {
    @Environment(\.palette) private var p
    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var managePath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    NavigationStack(path: $homePath) {
                        DashboardView(onOpenChat: { withAnimation { tab = .chat } })
                            .navigationDestination(for: HomeRoute.self) { route in
                                switch route {
                                case .activity: ActivityView()
                                case .models:   ModelListView()
                                case .settings: SettingsView()
                                }
                            }
                    }
                case .chat:
                    ChatView()
                case .manage:
                    NavigationStack(path: $managePath) {
                        BotsView()
                            .navigationDestination(for: ManageRoute.self) { route in
                                switch route {
                                case .settings: SettingsView()
                                }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            floatingBar
        }
        .background(p.bg.ignoresSafeArea())
    }

    private var floatingBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tabItem(.home, "首页", "house")
                tabItem(.chat, "聊天", "bubble.left")
                tabItem(.manage, "管理", "square.grid.2x2")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6)

            Button {
                withAnimation { tab = .home; homePath = NavigationPath() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(p.text)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .circle)
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabItem(_ t: AppTab, _ label: String, _ icon: String) -> some View {
        let on = tab == t
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? p.orange : p.textSecondary)
                Text(label)
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? p.orange : p.textSecondary)
            }
            .frame(width: 84)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat

struct ChatView: View {
    @Environment(\.palette) private var p
    @Environment(APIClient.self) private var client
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("聊天").font(.system(size: 30, weight: .black)).foregroundStyle(p.text)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)

            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .light)).foregroundStyle(p.textTertiary)
                Text("会话需在完整面板中打开").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
                Text("实时聊天依赖实例的消息通道（WebSocket），\n原生端尚未接入。").font(.system(size: 14))
                    .multilineTextAlignment(.center).foregroundStyle(p.textSecondary)
                Button {
                    var s = client.baseURL.absoluteString
                    if s.hasSuffix("/") { s.removeLast() }
                    if let u = URL(string: s + "/chat") { UIApplication.shared.open(u) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari").font(.system(size: 14))
                        Text("在浏览器中打开聊天").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(p.orange, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
    }
}