//
//  ConfigBrowserView.swift
//  MaiBot
//
//  麦麦设置（只读）：拉取 config/bot，用可展开的 JSON 树展示。
//

import SwiftUI

struct ConfigBrowserView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var root: [String: Any]?
    @State private var error: String?
    @State private var query = ""
    @State private var editingSection: String?
    @State private var sectionText = ""
    @State private var showSectionEditor = false
    @State private var showRaw = false
    @State private var rawText = ""
    @State private var saving = false
    @State private var saveMsg: String?
    @State private var confirmRaw = false

    private var flatMatches: [(String, String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let root else { return [] }
        var out: [(String, String)] = []
        func walk(_ v: Any, _ path: String, _ depth: Int) {
            guard out.count < 200, depth <= 8 else { return }
            if let d = v as? [String: Any] {
                for (k, sub) in d { walk(sub, path.isEmpty ? k : path + "." + k, depth + 1) }
            } else if let a = v as? [Any] {
                for (i, sub) in a.enumerated() { walk(sub, path + "[\(i)]", depth + 1) }
            } else {
                let s = scalarString(v)
                if path.lowercased().contains(q) || s.lowercased().contains(q) {
                    out.append((path, s))
                }
            }
        }
        walk(root, "", 0)
        return out
    }

    private func scalarString(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let e = error {
                    ErrorBanner(message: e) { Task { await load() } }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索配置项…", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 10) {
                    Menu("编辑配置节") {
                        ForEach(sectionKeys, id: \.self) { k in
                            Button(k) { openSection(k) }
                        }
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
                    Button("原始 TOML") { Task { await openRaw() } }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
                    Spacer()
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("匹配 \(flatMatches.count) 项").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                    ForEach(flatMatches, id: \.0) { item in
                        HStack(alignment: .top) {
                            Text(item.0).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textSecondary)
                            Spacer(minLength: 8)
                            Text(item.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.text).lineLimit(2)
                        }.padding(.vertical, 2)
                    }
                } else if let root {
                    JSONValueView(key: "config", value: root)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
                Text("可编辑：分节 JSON 或原始 TOML；保存会写入麦麦配置。")
                    .font(.system(size: 11)).foregroundStyle(p.textTertiary).padding(.top, 8)
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("麦麦设置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showSectionEditor) { sectionEditor }
        .sheet(isPresented: $showRaw) { rawEditor }
        .alert("提示", isPresented: Binding(get: { saveMsg != nil }, set: { if !$0 { saveMsg = nil } })) {
            Button("好") { saveMsg = nil }
        } message: { Text(saveMsg ?? "") }
    }

    private var sectionKeys: [String] { (root ?? [:]).keys.sorted() }

    private func pretty(_ v: Any) -> String {
        if let d = v as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), let str = String(data: data, encoding: .utf8) { return str }
        return "\(v)"
    }

    private func openSection(_ key: String) {
        guard let root, let v = root[key] as? [String: Any] else {
            saveMsg = "该配置节不是对象，无法按节编辑，请使用原始 TOML。"
            return
        }
        editingSection = key
        sectionText = pretty(v)
        showSectionEditor = true
    }

    private func saveSection() async {
        guard let key = editingSection else { return }
        guard let data = sectionText.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            saveMsg = "JSON 解析失败，请检查格式。"
            return
        }
        saving = true; defer { saving = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.saveBotSection(botID: id, section: key, value: obj)
            showSectionEditor = false
            await load()
            saveMsg = "已保存配置节：\(key)"
        } catch { saveMsg = "保存失败：\(error.localizedDescription)" }
    }

    private func openRaw() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            rawText = try await client.botConfigRaw(botID: id)
            showRaw = true
        } catch { saveMsg = "读取原始配置失败：\(error.localizedDescription)" }
    }

    private func saveRaw() async {
        saving = true; defer { saving = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.saveBotConfigRaw(botID: id, raw: rawText)
            showRaw = false
            await load()
            saveMsg = "已保存原始 TOML 配置。"
        } catch { saveMsg = "保存失败：\(error.localizedDescription)" }
    }

    private var sectionEditor: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $sectionText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
            }
            .background(p.bg)
            .navigationTitle("编辑节：" + (editingSection ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showSectionEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { Task { await saveSection() } }.disabled(saving)
                }
            }
        }
    }

    private var rawEditor: some View {
        NavigationStack {
            TextEditor(text: $rawText)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(p.bg)
                .navigationTitle("原始 TOML")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showRaw = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { confirmRaw = true }.disabled(saving)
                    }
                }
                .confirmationDialog("写入原始 TOML 可能影响麦麦运行，确认保存？", isPresented: $confirmRaw, titleVisibility: .visible) {
                    Button("确认保存", role: .destructive) { Task { await saveRaw() } }
                    Button("取消", role: .cancel) {}
                }
        }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.configBot(botID: id)
            if let dict = raw as? [String: Any] {
                root = (dict["config"] as? [String: Any]) ?? dict
            } else { root = ["value": raw] }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}

struct JSONValueView: View {
    @Environment(\.palette) private var p
    let key: String?
    let value: Any
    var depth: Int = 0
    @State private var expanded: Bool

    init(key: String?, value: Any, depth: Int = 0) {
        self.key = key
        self.value = value
        self.depth = depth
        _expanded = State(initialValue: depth <= 1)
    }

    var body: some View {
        if let dict = value as? [String: Any] {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(dict.keys.sorted(), id: \.self) { k in
                    JSONValueView(key: k, value: dict[k] ?? NSNull(), depth: depth + 1)
                }
            } label: {
                label(dict.count, suffix: "项")
            }
        } else if let arr = value as? [Any] {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(arr.indices, id: \.self) { i in
                    JSONValueView(key: "[\(i)]", value: arr[i], depth: depth + 1)
                }
            } label: {
                label(arr.count, suffix: "元素")
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                if let key { Text(key).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.textSecondary) }
                Spacer(minLength: 8)
                Text(scalar).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.text).lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    private func label(_ count: Int, suffix: String) -> some View {
        HStack {
            Text(key ?? "·").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(p.text)
            Text("\(count) \(suffix)").font(.system(size: 10)).foregroundStyle(p.textTertiary)
            Spacer()
        }
    }

    private var scalar: String {
        if let s = value as? String { return s.isEmpty ? "(空)" : s }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if value is NSNull { return "null" }
        return "\(value)"
    }
}
