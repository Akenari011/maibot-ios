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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let e = error {
                    Text(e).font(.system(size: 13)).foregroundStyle(.red)
                }
                if let root {
                    JSONValueView(key: "config", value: root)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
                Text("只读：此页仅展示配置，编辑请在网页版操作。")
                    .font(.system(size: 11)).foregroundStyle(p.textTertiary).padding(.top, 8)
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("麦麦设置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
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

    var body: some View {
        if let dict = value as? [String: Any] {
            DisclosureGroup {
                ForEach(dict.keys.sorted(), id: \.self) { k in
                    JSONValueView(key: k, value: dict[k] ?? NSNull())
                }
            } label: {
                label(dict.count, suffix: "项")
            }
        } else if let arr = value as? [Any] {
            DisclosureGroup {
                ForEach(arr.indices, id: \.self) { i in
                    JSONValueView(key: "[\(i)]", value: arr[i])
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
