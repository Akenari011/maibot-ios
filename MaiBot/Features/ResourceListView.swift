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

struct EmojiThumb: View {
    @Environment(APIClient.self) private var client
    let botID: String
    let emojiID: String
    var size: CGFloat = 44
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            if image == nil, let d = try? await client.emojiThumbnail(botID: botID, id: emojiID) {
                image = UIImage(data: d)
            }
        }
    }
}

struct ResourceItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    var avatar: String? = nil
}

struct PersonThumb: View {
    @Environment(APIClient.self) private var client
    let botID: String
    let platform: String
    let userID: String
    var size: CGFloat = 44
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Circle().fill(Color.secondary.opacity(0.15)) }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task {
            if image == nil, let d = try? await client.personAvatar(botID: botID, platform: platform, userID: userID) {
                image = UIImage(data: d)
            }
        }
    }
}

struct ResourceDetailView: View {
    let kind: ResourceKind
    let item: ResourceItem
    var botID: String = ""
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var data: Any?
    @State private var error: String?
    @State private var loading = true
    @State private var confirmDelete = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                    if kind == .emoji {
                        HStack { Spacer(); EmojiThumb(botID: botID, emojiID: item.id, size: 160); Spacer() }
                    }
                    if loading { ProgressView().padding(.top, 20) }
                    if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                    if let data { JSONValueView(key: nil, value: data) }
                    if kind == .emoji {
                        HStack(spacing: 10) {
                            Button("注册") { Task { await act("register") } }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8).background(p.green, in: Capsule())
                            Button("禁用") { Task { await act("ban") } }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8).background(p.orange, in: Capsule())
                            Button("删除") { confirmDelete = true }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8).background(.red, in: Capsule())
                        }
                        .disabled(busy)
                        .confirmationDialog("删除该表情？", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("删除", role: .destructive) { Task { await act("delete") } }
                            Button("取消", role: .cancel) {}
                        }
                    }
                    if kind == .expression || kind == .jargon {
                        HStack {
                            Button("删除") { confirmDelete = true }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8).background(.red, in: Capsule())
                                .disabled(busy)
                        }
                        .confirmationDialog("删除该条目？", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("删除", role: .destructive) { Task { await act("delete") } }
                            Button("取消", role: .cancel) {}
                        }
                    }
                    if kind == .person {
                        Text("只读：人物资料编辑请在网页版操作。").font(.system(size: 11)).foregroundStyle(p.textTertiary)
                    }
                }
                .padding(16)
            }
            .background(p.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { await load() }
        }
    }

    private func act(_ action: String) async {
        busy = true; defer { busy = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            switch action {
            case "register": _ = try await client.emojiRegister(botID: id, id: item.id)
            case "ban": _ = try await client.emojiBan(botID: id, id: item.id)
            case "delete":
                if kind == .emoji { _ = try await client.emojiDelete(botID: id, id: item.id) }
                else { _ = try await client.resourceDelete(botID: id, path: kind.path, id: item.id) }
            default: break
            }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.resourceDetail(botID: id, path: kind.path, id: item.id)
            if let d = raw as? [String: Any] { data = d["data"] ?? d["detail"] ?? d } else { data = raw }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
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
    @State private var selected: ResourceItem?
    @State private var botID = ""
    @State private var creating = false
    @State private var f1 = ""
    @State private var f2 = ""
    @State private var saving = false

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
                if kind == .expression || kind == .jargon {
                    Button { f1 = ""; f2 = ""; creating = true } label: {
                        Text("＋ 新增").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(p.orange, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Text("\(kind.title)（共 \(total)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                if items.isEmpty && !loading {
                    Text("暂无数据").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
                ForEach(items) { it in
                    Button { selected = it } label: {
                        Panel(padding: 14) {
                            HStack(alignment: .top, spacing: 10) {
                            if kind == .emoji && !botID.isEmpty { EmojiThumb(botID: botID, emojiID: it.id) }
                            if kind == .person, let av = it.avatar, !botID.isEmpty {
                                let parts = av.split(separator: "|", maxSplits: 1).map(String.init)
                                if parts.count == 2 { PersonThumb(botID: botID, platform: parts[0], userID: parts[1]) }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(2)
                                if !it.subtitle.isEmpty {
                                    Text(it.subtitle).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2)
                                }
                                if !it.detail.isEmpty {
                                    Text(it.detail).font(.system(size: 11)).foregroundStyle(p.textTertiary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            }
                        }
                    }.buttonStyle(.plain)
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
        .sheet(item: $selected) { it in ResourceDetailView(kind: kind, item: it, botID: botID) }
        .sheet(isPresented: $creating) { createSheet }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section(kind == .expression ? "情景" : "黑话内容") { TextField("", text: $f1) }
                Section(kind == .expression ? "风格" : "含义") { TextField("", text: $f2) }
                Section {
                    Button(saving ? "保存中…" : "保存（全局）") { Task { await create() } }
                        .disabled(saving || f1.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("新增" + kind.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { creating = false } } }
        }
    }

    private func create() async {
        saving = true; defer { saving = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let body: [String: Any] = kind == .expression
                ? ["situation": f1, "style": f2, "is_global": true]
                : ["content": f1, "meaning": f2, "is_global": true]
            _ = try await client.resourceCreate(botID: id, path: kind.path, body: body)
            creating = false
            await load(reset: true)
        } catch { self.error = error.localizedDescription }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if reset { page = 1 }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            botID = id
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
                                detail: "认识 \(num("know_times")) 次",
                                avatar: str("platform") + "|" + str("user_id"))
        }
    }
}
