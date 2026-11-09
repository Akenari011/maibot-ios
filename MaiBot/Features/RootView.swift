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
enum HomeRoute: Hashable { case activity, models, settings, logs, files, news, gated(String) }
enum ManageRoute: Hashable { case bots, models, statistics, config, plugins, memory, prompts, files, adapter, reasoning, settings, logs, other(String) }

struct MainShell: View {
    @Environment(\.palette) private var p
    @State private var tab: AppTab
    @State private var homePath: NavigationPath
    @State private var managePath: NavigationPath
    @Namespace private var tabNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        var hp = NavigationPath()
        var mp = NavigationPath()
        let start: AppTab
        switch TestSupport.startTab {
        case "chat", "room": start = .chat
        case "manage":   start = .manage
        case "logs":     start = .home; hp.append(HomeRoute.logs)
        case "settings": start = .home; hp.append(HomeRoute.settings)
        case "bots":     start = .manage; mp.append(ManageRoute.bots)
        case "stats":    start = .manage; mp.append(ManageRoute.statistics)
        case "config":   start = .manage; mp.append(ManageRoute.config)
        case "plugins":  start = .manage; mp.append(ManageRoute.plugins)
        case "memory":   start = .manage; mp.append(ManageRoute.memory)
        case "prompts":  start = .manage; mp.append(ManageRoute.prompts)
        case "files":    start = .manage; mp.append(ManageRoute.files)
        case "news":     start = .home; hp.append(HomeRoute.news)
        default:         start = .home
        }
        _tab = State(initialValue: start)
        _homePath = State(initialValue: hp)
        _managePath = State(initialValue: mp)
    }

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
                                case .logs:     LogsView()
                                case .files:    FilesView()
                                case .news:     NewsListView()
                                case .gated(let t): PlaceholderPage(title: t)
                                }
                            }
                    }
                case .chat:
                    if TestSupport.startTab == "room" { ChatView() }
                    else { NavigationStack { ChatListView() } }
                case .manage:
                    NavigationStack(path: $managePath) {
                        ManagementIndexView()
                            .navigationDestination(for: ManageRoute.self) { route in
                                switch route {
                                case .bots:      BotsView()
                                case .models:    ModelListView()
                                case .statistics: StatisticsView()
                                case .config:    ConfigBrowserView()
                                case .plugins:   PluginsView()
                                case .memory:    MemorySourcesView()
                                case .prompts:   PromptsView()
                                case .files:     FilesView()
                                case .adapter:   AdapterConfigView()
                                case .reasoning: ReasoningView()
                                case .settings:  SettingsView()
                                case .logs:      LogsView()
                                case .other(let title): PlaceholderPage(title: title)
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
                tabItem(.chat, "聊天", "message")
                tabItem(.manage, "管理", "square.grid.2x2")
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6)

            Button {
                withAnimation(Motion.tab) { tab = .home; homePath = NavigationPath() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(p.text)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabItem(_ t: AppTab, _ label: String, _ icon: String) -> some View {
        let on = tab == t
        return Button {
            withAnimation(reduceMotion ? nil : Motion.tab) { tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? p.orange : p.text)
                    .scaleEffect(on ? 1.06 : 1)
                Text(label)
                    .font(.system(size: 10, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? p.orange : p.text)
            }
            .frame(width: 84)
            .padding(.vertical, 4)
            .background {
                if on {
                    Capsule().fill(p.orange.opacity(0.12))
                        .matchedGeometryEffect(id: "tabIndicator", in: tabNS)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat (native, over websocket)

struct ChatView: View {
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var chat: ChatClient?
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let chat {
                transcript(chat)
                inputBar(chat)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await chat?.connect() } } else { chat?.disconnect() }
        }
        .navigationTitle("聊天")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if chat == nil {
                let c = ChatClient(client: client)
                chat = c
                await c.connect()
                if let t = ProcessInfo.processInfo.environment["GM_TEST_CHAT_TEXT"], !t.isEmpty {
                    try? await Task.sleep(for: .seconds(2))
                    c.send(t)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let chat {
                switch chat.status {
                case .ready:
                    statusDot("已连接", p.green)
                case .connecting:
                    statusDot("连接中…", p.orange)
                case .idle:
                    statusDot("未连接", p.textTertiary)
                case .failed(let m):
                    statusDot("连接失败", .red).help(m)
                }
                if case .ready = chat.status {
                    Text(chat.peerName).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text).lineLimit(1)
                }
            }
            Spacer()
            if case .failed = chat?.status {
                Button("重连") { Task { await chat?.connect() } }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5) }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
    }

    private func avatar(bot: Bool) -> some View {
        ZStack {
            Circle().fill(bot ? p.orange : p.iconCircle).frame(width: 32, height: 32)
            Image(systemName: bot ? "sparkles" : "person.fill")
                .font(.system(size: 15)).foregroundStyle(bot ? .white : p.textSecondary)
        }
    }

    private func statusDot(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(c)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(c.opacity(0.12), in: .capsule)
    }

    private func transcript(_ chat: ChatClient) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if chat.messages.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40, weight: .light)).foregroundStyle(p.textTertiary)
                            Text("和" + chat.peerName + "说点什么").font(.system(size: 15)).foregroundStyle(p.textSecondary)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(chat.messages.indices, id: \.self) { idx in
                        let m = chat.messages[idx]
                        bubble(m, showMeta: idx == 0 || chat.messages[idx - 1].role != m.role)
                    }
                    if chat.waiting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(chat.peerName + "正在输入…").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: chat.messages.last?.text ?? "") { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage, showMeta: Bool) -> some View {
        if m.role == .system {
            HStack {
                Spacer()
                Text(m.text)
                    .font(.system(size: 12))
                    .foregroundStyle(p.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        } else {
            VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 3) {
                if showMeta {
                    let name = m.sender.isEmpty ? (m.role == .bot ? "麦麦" : "我") : m.sender
                    Text(m.time.isEmpty ? name : "\(name) · \(m.time)")
                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if m.role == .user { Spacer(minLength: 40) }
                    if m.role == .bot { avatar(bot: true) }
                    Text(m.text)
                        .font(.system(size: 15))
                        .foregroundStyle(m.role == .user ? .white : p.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(m.role == .user ? p.orange : p.iconCircle,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .textSelection(.enabled)
                        .frame(maxWidth: 280, alignment: m.role == .user ? .trailing : .leading)
                    if m.role == .user { avatar(bot: false) }
                    if m.role == .bot { Spacer(minLength: 40) }
                }
            }
        }
    }

    private func sendDraft(_ chat: ChatClient) {
        guard case .ready = chat.status else { return }
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        chat.send(t)
        inputFocused = true
    }

    private func inputBar(_ chat: ChatClient) -> some View {
        HStack(spacing: 10) {
            TextField("发送消息…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { sendDraft(chat) }
                .font(.system(size: 15))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(p.iconCircle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                sendDraft(chat)
            } label: {
                let ready = { if case .ready = chat.status { return true } else { return false } }()
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background((draft.trimmingCharacters(in: .whitespaces).isEmpty || !ready) ? Color(hex: 0xB2B0AB) : p.orange, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled({ if case .ready = chat.status { return draft.trimmingCharacters(in: .whitespaces).isEmpty } else { return true } }())
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 84)
    }
}