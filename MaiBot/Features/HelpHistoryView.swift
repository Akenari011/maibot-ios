import SwiftUI

struct HelpSessionRow: Identifiable {
    let id: String
    let title: String
    let time: String
}

struct HelpHistoryView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var rows: [HelpSessionRow] = []
    @State private var error: String?
    @State private var loading = true
    @State private var selected: HelpSessionRow?
    @State private var detail: Any?
    @State private var detailLoading = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                Text("答疑会话（\(rows.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                if rows.isEmpty && !loading {
                    Text("暂无答疑历史").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
                ForEach(rows) { r in
                    Button { Task { await open(r) } } label: {
                        Panel(padding: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(2)
                                if !r.time.isEmpty { Text(r.time).font(.system(size: 11)).foregroundStyle(p.textTertiary) }
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("帮助历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { r in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(r.title).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                        if detailLoading { ProgressView() }
                        if let detail { JSONValueView(key: nil, value: detail) }
                    }.padding(16)
                }
                .background(p.bg)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { selected = nil } }
                    ToolbarItem(placement: .destructiveAction) { Button("删除") { confirmDelete = true } }
                }
                .confirmationDialog("删除该答疑会话？", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { Task { await remove(r) } }
                    Button("取消", role: .cancel) {}
                }
            }
        }
    }

    private func open(_ r: HelpSessionRow) async {
        selected = r; detail = nil; detailLoading = true; defer { detailLoading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            detail = try await client.helpSessionDetail(botID: id, id: r.id)
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ r: HelpSessionRow) async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.deleteHelpSession(botID: id, id: r.id)
            selected = nil
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.helpSessions(botID: id)
            let list = raw as? [[String: Any]] ?? []
            rows = list.map { m in
                HelpSessionRow(id: (m["session_id"] as? String) ?? (m["id"] as? String) ?? UUID().uuidString,
                               title: (m["title"] as? String) ?? (m["question"] as? String) ?? "答疑会话",
                               time: (m["created_at"] as? String) ?? "")
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
