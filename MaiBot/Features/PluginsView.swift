import SwiftUI

struct PluginRow: Identifiable {
    let id: String
    let name: String
    let version: String
    let desc: String
    let author: String
    let enabled: Bool
    let loaded: Bool
    let loadError: String
}

struct PluginsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [PluginRow] = []
    @State private var error: String?
    @State private var search = ""
    @State private var detail: PluginRow?

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
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if filtered.isEmpty { Text("暂无插件").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30) }
                ForEach(filtered) { it in
                    Panel(padding: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Button { detail = it } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(it.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                    Text("v" + it.version).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                                    Spacer()
                                }
                                Text(it.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(1)
                                if !it.desc.isEmpty { Text(it.desc).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2) }
                                if !it.author.isEmpty { Text("作者：" + it.author).font(.system(size: 11)).foregroundStyle(p.textTertiary) }
                                if !it.loadError.isEmpty {
                                    Text("加载失败：" + it.loadError).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Spacer(minLength: 4)
                            Toggle("", isOn: Binding(get: { it.enabled }, set: { v in Task { await toggle(it, v) } }))
                                .labelsHidden()
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .pageChrome("插件配置")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $detail) { d in PluginDetailView(pluginID: d.id, name: d.name) }
    }

    private func toggle(_ row: PluginRow, _ value: Bool) async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.togglePlugin(botID: id, pluginID: row.id)
            await load()
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
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
                                 author: author,
                                 enabled: (m["enabled"] as? Bool) ?? false,
                                 loaded: (m["loaded"] as? Bool) ?? false,
                                 loadError: (m["load_error"] as? String) ?? "")
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
