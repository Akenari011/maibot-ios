import SwiftUI

struct MonitorView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var sessions: [ChatStream] = []
    @State private var selectedID = ""
    @State private var ctx: [String: Any] = [:]
    @State private var error: String?
    @State private var loading = true

    private var memoryTexts: [String] {
        (ctx["memory"] as? [String]) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !sessions.isEmpty {
                    Menu {
                        ForEach(sessions) { s in
                            Button(s.displayName) { selectedID = s.sessionID; Task { await load() } }
                        }
                    } label: {
                        HStack {
                            Text(sessions.first(where: { $0.sessionID == selectedID })?.displayName ?? "选择会话")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(p.text).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 20) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if let ra = ctx["runtime_active"] {
                    Text("运行时：" + String(describing: ra)).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                if !memoryTexts.isEmpty {
                    Text("上下文记忆（\(memoryTexts.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    ForEach(Array(memoryTexts.enumerated()), id: \.offset) { _, t in
                        Panel(padding: 12) {
                            Text(t).font(.system(size: 12)).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(["expressions", "jargon", "tools"], id: \.self) { key in
                    if let v = ctx[key] {
                        Text(key).font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(.top, 4)
                        Panel(padding: 12) {
                            JSONValueView(key: nil, value: v)
                        }
                    }
                }
                Text("数据来自 reasoning-process/active-context（只读）。")
                    .font(.system(size: 10)).foregroundStyle(p.textTertiary)
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome("监控")
        .refreshable { await load() }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await load(silent: true)
            }
        }
    }

    private func load(silent: Bool = false) async {
        if !silent { loading = true }
        defer { if !silent { loading = false } }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            if sessions.isEmpty { sessions = try await client.chatStreams(botID: id) }
            if selectedID.isEmpty { selectedID = sessions.first?.sessionID ?? "" }
            guard !selectedID.isEmpty else { return }
            let raw = try await client.activeContext(botID: id, sessionID: selectedID)
            ctx = raw as? [String: Any] ?? [:]
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
