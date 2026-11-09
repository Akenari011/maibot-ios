import SwiftUI

enum ResourceKind: String, CaseIterable, Identifiable {
    case emoji, expression, jargon, person
    var id: String { rawValue }
    var title: String {
        switch self {
        case .emoji: return "表情"
        case .expression: return "表达方式"
        case .jargon: return "黑话"
        case .person: return "人物"
        }
    }
    var path: String {
        switch self {
        case .emoji: return "emoji/list"
        case .expression: return "expression/list"
        case .jargon: return "jargon/list"
        case .person: return "person/list"
        }
    }
}

struct ResourceItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
}

struct ResourceListView: View {
    let kind: ResourceKind
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [ResourceItem] = []
    @State private var total = 0
    @State private var page = 1
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索" + kind.title + "…", text: $query)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await load(reset: true) } }
                    Button("搜索") { Task { await load(reset: true) } }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(p.orange)
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                if let e = error { ErrorBanner(message: e) { Task { await load(reset: true) } } }
                Text("\(kind.title)（共 \(total)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                if items.isEmpty && !loading {
                    Text("暂无数据").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
                ForEach(items) { it in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(2)
                            if !it.subtitle.isEmpty {
                                Text(it.subtitle).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2)
                            }
                            if !it.detail.isEmpty {
                                Text(it.detail).font(.system(size: 11)).foregroundStyle(p.textTertiary).lineLimit(1)
                            }
                        }
                    }
                }
                if items.count < total {
                    Button {
                        Task { await load(reset: false) }
                    } label: {
                        Text(loading ? "加载中…" : "加载更多（\(items.count)/\(total)）")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(reset: true) }
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if reset { page = 1 }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.resourcePage(botID: id, path: kind.path, page: page, search: query)
            let dict = raw as? [String: Any] ?? [:]
            total = (dict["total"] as? Int) ?? Int((dict["total"] as? Double) ?? 0)
            let data = dict["data"] as? [[String: Any]] ?? []
            let mapped = data.map { m in map(m) }
            items = reset ? mapped : items + mapped
            page += 1
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }

    private func map(_ m: [String: Any]) -> ResourceItem {
        func str(_ k: String) -> String { (m[k] as? String) ?? "" }
        func num(_ k: String) -> Int { (m[k] as? Int) ?? Int((m[k] as? Double) ?? 0) }
        switch kind {
        case .emoji:
            let desc = str("description")
            return ResourceItem(id: String(num("id")),
                                title: desc.isEmpty ? "表情 #\(num("id"))" : desc,
                                subtitle: str("format") + " · " + str("status"),
                                detail: "使用 \(num("usage_count")) · 查询 \(num("query_count"))")
        case .expression:
            return ResourceItem(id: String(num("id")),
                                title: str("situation"),
                                subtitle: str("style"),
                                detail: str("chat_name"))
        case .jargon:
            let meaning = str("meaning")
            return ResourceItem(id: String(num("id")),
                                title: str("content"),
                                subtitle: meaning.isEmpty ? "(未推断含义)" : meaning,
                                detail: str("chat_name") + " · \(num("count")) 次")
        case .person:
            let name = str("person_name").isEmpty ? str("nickname") : str("person_name")
            return ResourceItem(id: String(num("id")),
                                title: name.isEmpty ? "未命名" : name,
                                subtitle: str("platform") + " · " + str("user_id"),
                                detail: "认识 \(num("know_times")) 次")
        }
    }
}
