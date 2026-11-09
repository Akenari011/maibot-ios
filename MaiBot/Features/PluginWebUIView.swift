import SwiftUI

struct PluginWebUIView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var extensions: [[String: Any]] = []
    @State private var error: String?
    @State private var loading = true

    private var firstPage: (String, [String: Any])? {
        for e in extensions {
            let pid = (e["plugin_id"] as? String) ?? ""
            if let pages = e["pages"] as? [[String: Any]], let first = pages.first { return (pid, first) }
        }
        return nil
    }

    var body: some View {
        if TestSupport.effectiveTab == "pluginAuto", let fp = firstPage {
            PluginPageView(pluginID: fp.0, page: fp.1)
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if extensions.isEmpty && !loading && error == nil {
                    Text("暂无插件扩展页面").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
                ForEach(Array(extensions.enumerated()), id: \.offset) { _, ext in
                    let title = (ext["workspace_title"] as? String) ?? (ext["plugin_id"] as? String) ?? "插件"
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary)
                        ForEach(Array(((ext["pages"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, page in
                            NavigationLink {
                                PluginPageView(pluginID: (ext["plugin_id"] as? String) ?? "", page: page)
                            } label: {
                                Panel(padding: 14) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text((page["title"] as? String) ?? "页面").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                                        if let d = page["description"] as? String, !d.isEmpty {
                                            Text(d).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2)
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome("插件扩展")
        .refreshable { await load() }
        .task { await load() }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.pluginWebUI(botID: id)
            extensions = (raw as? [String: Any])?["extensions"] as? [[String: Any]] ?? []
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}

struct PluginPageView: View {
    let pluginID: String
    let page: [String: Any]
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var queries: [String: Any] = [:]
    @State private var values: [String: Any] = [:]
    @State private var error: String?
    @State private var loading = true
    @State private var busy = false
    @State private var customHTML: String?
    @State private var customError: String?

    private var pageID: String { (page["id"] as? String) ?? "" }
    private var title: String { (page["title"] as? String) ?? "插件页面" }
    private var content: [[String: Any]] { (page["content"] as? [[String: Any]]) ?? [] }
    private var queryDefs: [String: Any] { (page["queries"] as? [String: Any]) ?? [:] }
    private var actionDefs: [String: Any] { (page["actions"] as? [String: Any]) ?? [:] }
    private var isDeclarative: Bool { (page["mode"] as? String) == "declarative" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await reload() } } }
                if !isDeclarative && !loading {
                    if let html = customHTML {
                        CustomPluginWebView(html: html, baseURL: client.baseURL)
                            .frame(minHeight: 600)
                    } else {
                        Text(customError ?? "正在加载插件页面…").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    }
                }
                if isDeclarative {
                    ForEach(Array(content.enumerated()), id: \.offset) { _, node in
                        render(node)
                    }
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome(title)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func render(_ n: [String: Any]) -> AnyView {
        let type = (n["type"] as? String) ?? ""
        let label = (n["label"] as? String) ?? ""
        switch type {
        case "stack", "card", "tabs":
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                if !label.isEmpty { Text(label).font(.system(size: 12)).foregroundStyle(p.textSecondary) }
                ForEach(Array(((n["children"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, c in render(c) }
            }.padding(12).background(p.card, in: RoundedRectangle(cornerRadius: 12)))
        case "grid":
            return AnyView(LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(Array(((n["children"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, c in render(c) }
            })
        case "collapsible":
            return AnyView(DisclosureGroup {
                ForEach(Array(((n["children"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, c in render(c) }
            } label: { Text(label.isEmpty ? "详情" : label).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text) })
        case "text":
            return AnyView(Text(valueString(n["value"]))
                .font(.system(size: 12, design: (n["format"] as? String) == "log" ? .monospaced : .default))
                .foregroundStyle(p.textSecondary).fixedSize(horizontal: false, vertical: true))
        case "stat":
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(p.textSecondary) }
                Text(valueString(n["value"])).font(.system(size: 18, weight: .semibold)).foregroundStyle(p.text)
            }.frame(maxWidth: .infinity, alignment: .leading))
        case "progress":
            let pct = (n["value"] as? Double) ?? Double((n["value"] as? Int) ?? 0)
            return AnyView(VStack(alignment: .leading, spacing: 3) {
                if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(p.textSecondary) }
                ProgressView(value: min(max(pct, 0), 100), total: 100).tint(p.orange)
            })
        case "table":
            return AnyView(tableNode(n))
        case "input", "date":
            let nm = (n["name"] as? String) ?? ""
            return AnyView(VStack(alignment: .leading, spacing: 3) {
                if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(p.textSecondary) }
                TextField("", text: Binding(get: { (values[nm] as? String) ?? "" }, set: { values[nm] = $0 }))
                    .font(.system(size: 13)).padding(8)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }
            })
        case "switch":
            let nm = (n["name"] as? String) ?? ""
            return AnyView(Toggle(label, isOn: Binding(get: { (values[nm] as? Bool) ?? false }, set: { values[nm] = $0 }))
                .tint(p.orange).font(.system(size: 13)))
        case "select":
            let nm = (n["name"] as? String) ?? ""
            let opts = (n["options"] as? [[String: Any]]) ?? []
            return AnyView(VStack(alignment: .leading, spacing: 3) {
                if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(p.textSecondary) }
                Picker(label, selection: Binding(get: { (values[nm] as? String) ?? "" }, set: { values[nm] = $0 })) {
                    ForEach(Array(opts.enumerated()), id: \.offset) { _, o in
                        Text((o["label"] as? String) ?? "").tag((o["value"] as? String) ?? "")
                    }
                }.pickerStyle(.menu)
            })
        case "button":
            let action = (n["action"] as? String) ?? ""
            return AnyView(Button { Task { await invoke(action) } } label: {
                Text(label.isEmpty ? "操作" : label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(p.orange, in: Capsule())
            }.buttonStyle(.plain).disabled(busy))
        default:
            return AnyView(EmptyView())
        }
    }
    private func tableNode(_ n: [String: Any]) -> AnyView {
        let cols = (n["columns"] as? [[String: Any]]) ?? []
        let rows = (n["value"] as? [String: Any]).flatMap { resolve($0) } as? [[String: Any]] ?? []
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.prefix(50).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { _, c in
                        let f = (c["field"] as? String) ?? ""
                        HStack {
                            Text((c["label"] as? String) ?? f).font(.system(size: 11)).foregroundStyle(p.textSecondary)
                            Spacer()
                            Text(row[f].map { "\($0)" } ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(p.text).lineLimit(1)
                        }
                    }
                }.padding(8).background(p.card, in: RoundedRectangle(cornerRadius: 8))
            }
        })
    }
    private func resolve(_ ref: [String: Any]) -> Any? {
        guard let source = ref["source"] as? String, let field = ref["field"] as? String else { return nil }
        var cur: Any? = queries[source]
        for comp in field.split(separator: ".") {
            if let d = cur as? [String: Any] { cur = d[String(comp)] }
            else if let a = cur as? [Any], let i = Int(comp), i < a.count { cur = a[i] }
            else { return nil }
        }
        return cur
    }

    private func valueString(_ v: Any?) -> String {
        if let ref = v as? [String: Any], ref["scope"] != nil { return resolve(ref).map { "\($0)" } ?? "—" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if v == nil { return "—" }
        return "\(v!)"
    }

    private func reload() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            if !isDeclarative {
                do { customHTML = try await client.pluginDocumentText(botID: id, pluginID: pluginID, pageID: pageID) }
                catch { customError = error.localizedDescription }
                error = nil
                return
            }
            for name in queryDefs.keys.sorted() {
                let args = values.reduce(into: [String: Any]()) { acc, kv in acc[kv.key] = kv.value }
                queries[name] = try await client.pluginInvoke(botID: id, pluginID: pluginID, pageID: pageID, kind: "queries", name: name, args: args)
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }

    private func invoke(_ action: String) async {
        guard !action.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let args = values.reduce(into: [String: Any]()) { acc, kv in acc[kv.key] = kv.value }
            _ = try await client.pluginInvoke(botID: id, pluginID: pluginID, pageID: pageID, kind: "actions", name: action, args: args)
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}
