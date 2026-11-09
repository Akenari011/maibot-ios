import SwiftUI

struct MemorySourceRow: Identifiable {
    let id: String
    let name: String
    let count: Int
    let kind: String
}

struct MemorySourcesView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [MemorySourceRow] = []
    @State private var error: String?
    @State private var query = ""
    @State private var results: Any?
    @State private var searching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索记忆记录…", text: $query).font(.system(size: 14))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Button(searching ? "…" : "搜索") { Task { await search() } }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
                        .disabled(searching)
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                if let results {
                    Text("搜索结果").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    Panel(padding: 12) { JSONValueView(key: nil, value: results) }
                }
                Text("记忆来源（\(items.count)）").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if items.isEmpty { Text("暂无记忆来源").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30) }
                ForEach(items) { it in
                    Panel(padding: 14) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName(it)).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                Text(it.kind).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                            }
                            Spacer()
                            Text("\(it.count)").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(p.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .pageChrome("知识库")
        .refreshable { await load() }
        .task { await load() }
    }

    private func displayName(_ it: MemorySourceRow) -> String {
        if !it.name.isEmpty { return it.name }
        let labels = ["person_fact": "人物事实", "chat_summary": "聊天摘要",
                      "knowledge": "知识", "paragraph": "段落"]
        let label = labels[it.kind] ?? (it.kind.isEmpty ? "记忆" : it.kind)
        let raw = it.id.contains(":") ? String(it.id.split(separator: ":").last ?? "") : it.id
        return label + " · " + String(raw.prefix(8))
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = nil; return }
        searching = true; defer { searching = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            results = try await client.memorySearch(botID: id, query: q)
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.memorySources(botID: id)
            let list = (raw as? [String: Any])?["items"] as? [[String: Any]] ?? []
            items = list.map { m in
                MemorySourceRow(id: (m["source"] as? String) ?? "",
                                name: (m["chat_name"] as? String) ?? (m["person_name"] as? String) ?? "",
                                count: (m["count"] as? Int) ?? Int((m["count"] as? Double) ?? 0),
                                kind: (m["source_kind"] as? String) ?? "")
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
