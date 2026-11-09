import SwiftUI

struct MarketRow: Identifiable {
    let id: String
    let name: String
    let version: String
    let desc: String
}

struct MarketplaceView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var rows: [MarketRow] = []
    @State private var query = ""
    @State private var rawFallback: Any?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if !rows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                        TextField("搜索市场插件…", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                    Text("市场插件（共 \(rows.count)，显示 \(min(filtered.count, 200))）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    ForEach(filtered.prefix(200)) { r in
                        Panel(padding: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                    Text("v" + r.version).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                                    Spacer()
                                }
                                if !r.desc.isEmpty { Text(r.desc).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2) }
                            }
                        }
                    }
                } else if let rawFallback {
                    JSONValueView(key: nil, value: rawFallback)
                } else if !loading && error == nil {
                    Text("市场暂无数据").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("插件市场")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var filtered: [MarketRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.marketplace(botID: id)
            rows = []
            rawFallback = nil
            if let dict = raw as? [String: Any] {
                let list = (dict["plugins"] as? [[String: Any]])
                    ?? (dict["items"] as? [[String: Any]])
                    ?? (dict["entries"] as? [[String: Any]])
                    ?? []
                if !list.isEmpty {
                    rows = list.map { m in
                        let man = m["manifest"] as? [String: Any] ?? [:]
                        return MarketRow(id: (m["id"] as? String) ?? (man["id"] as? String) ?? UUID().uuidString,
                                         name: (man["name"] as? String) ?? (m["name"] as? String) ?? "—",
                                         version: (man["version"] as? String) ?? (m["version"] as? String) ?? "—",
                                         desc: (man["description"] as? String) ?? (m["description"] as? String) ?? "")
                    }
                } else { rawFallback = raw }
            } else { rawFallback = raw }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
