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

struct MainShell: View {
    @Environment(\.palette) private var p
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:   DashboardView()
                case .chat:   ChatView()
                case .manage: ManageView()
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
            .background(.white, in: .capsule)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)

            Button {} label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(p.text)
                    .frame(width: 56, height: 56)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
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

// MARK: - Manage

struct ManageView: View {
    var body: some View {
        NavigationStack {
            BotsView()
                .navigationDestination(for: ManageRoute.self) { route in
                    switch route {
                    case .settings: SettingsView()
                    }
                }
        }
    }
}

enum ManageRoute: Hashable { case settings }

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
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .light)).foregroundStyle(p.textTertiary)
                Text("暂无会话").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
                Text("麦麦的聊天需要接入实例消息通道，\n当前版本尚未开放。").font(.system(size: 14))
                    .multilineTextAlignment(.center).foregroundStyle(p.textSecondary)
            }
            Spacer()

            HStack(spacing: 10) {
                TextField("发送消息…", text: $draft)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(p.card, in: .capsule)
                    .overlay { Capsule().strokeBorder(p.separator) }
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(p.orange, in: .circle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 84)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
    }
}