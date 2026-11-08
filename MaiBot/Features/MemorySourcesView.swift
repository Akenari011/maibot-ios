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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("记忆来源（\(items.count)）").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                if let e = error { Text(e).font(.system(size: 13)).foregroundStyle(.red) }
                if items.isEmpty { Text("暂无记忆来源").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30) }
                ForEach(items) { it in
                    Panel(padding: 14) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.name.isEmpty ? it.id : it.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
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
        .navigationTitle("长期记忆")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
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
