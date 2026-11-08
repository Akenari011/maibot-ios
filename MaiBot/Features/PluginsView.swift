import SwiftUI

struct PluginRow: Identifiable {
    let id: String
    let name: String
    let version: String
    let desc: String
    let author: String
}

struct PluginsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [PluginRow] = []
    @State private var error: String?
    @State private var search = ""

    private var filtered: [PluginRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? items : items.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) || $0.desc.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索插件…", text: $search).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                Text("插件（\(filtered.count)）").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                if let e = error { Text(e).font(.system(size: 13)).foregroundStyle(.red) }
                ForEach(filtered) { it in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(it.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                Text("v" + it.version).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                                Spacer()
                            }
                            Text(it.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(1)
                            if !it.desc.isEmpty { Text(it.desc).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2) }
                            if !it.author.isEmpty { Text("作者：" + it.author).font(.system(size: 11)).foregroundStyle(p.textTertiary) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .navigationTitle("插件配置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.pluginsInstalled(botID: id)
            let list = (raw as? [String: Any])?["plugins"] as? [[String: Any]] ?? []
            items = list.map { m in
                let man = m["manifest"] as? [String: Any] ?? [:]
                let author = ((man["author"] as? [String: Any])?["name"] as? String) ?? ""
                return PluginRow(id: (m["id"] as? String) ?? "",
                                 name: (man["name"] as? String) ?? (m["id"] as? String) ?? "—",
                                 version: (man["version"] as? String) ?? "—",
                                 desc: (man["description"] as? String) ?? "",
                                 author: author)
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
