import SwiftUI

struct PromptRow: Identifiable {
    let id: String
    let display: String
    let desc: String
    let customized: Bool
}

struct PromptsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var languages: [String] = []
    @State private var selected: String = ""
    @State private var filesByLang: [String: [PromptRow]] = [:]
    @State private var error: String?

    private var current: [PromptRow] { filesByLang[selected] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if languages.count > 1 {
                    SegmentedChips(items: languages, label: { $0 }, selection: $selected)
                }
                if let e = error { Text(e).font(.system(size: 13)).foregroundStyle(.red) }
                Text("提示词（\(current.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                ForEach(current) { f in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(f.display).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                if f.customized {
                                    Text("自定义").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.orange)
                                }
                                Spacer()
                            }
                            Text(f.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(1)
                            if !f.desc.isEmpty { Text(f.desc).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .navigationTitle("提示词管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.configPrompts(botID: id)
            let root = raw as? [String: Any] ?? [:]
            languages = (root["languages"] as? [String]) ?? []
            let files = root["files"] as? [String: [[String: Any]]] ?? [:]
            var map: [String: [PromptRow]] = [:]
            for (lang, arr) in files {
                map[lang] = arr.map { m in
                    PromptRow(id: (m["name"] as? String) ?? "",
                              display: (m["display_name"] as? String) ?? (m["name"] as? String) ?? "—",
                              desc: (m["description"] as? String) ?? "",
                              customized: (m["customized"] as? Bool) ?? false)
                }
            }
            filesByLang = map
            selected = languages.contains("zh-CN") ? "zh-CN" : (languages.first ?? "")
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
