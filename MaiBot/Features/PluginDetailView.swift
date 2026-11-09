import SwiftUI

struct PluginDetailView: View {
    let pluginID: String
    let name: String
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var config: Any?
    @State private var raw: Any?
    @State private var schema: Any?
    @State private var tab = 0
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(name).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                    Text(pluginID).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                    if loading { ProgressView().padding(.top, 20) }
                    if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                    Picker("视图", selection: $tab) {
                        Text("配置").tag(0)
                        Text("原始").tag(1)
                        Text("Schema").tag(2)
                    }.pickerStyle(.segmented)
                    if tab == 0, let config { Panel(padding: 12) { JSONValueView(key: nil, value: config) } }
                    if tab == 1, let raw { Panel(padding: 12) { JSONValueView(key: nil, value: raw) } }
                    if tab == 2, let schema { Panel(padding: 12) { JSONValueView(key: nil, value: schema) } }
                    Text("只读：插件配置编辑请在网页版进行。")
                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                }
                .padding(16)
            }
            .background(p.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.pluginConfig(botID: id, pluginID: pluginID)
            if let d = raw as? [String: Any] {
                config = d["config"] ?? d["data"] ?? d
            } else { config = raw }
            raw = try? await client.pluginRaw(botID: id, pluginID: pluginID)
            schema = try? await client.pluginSchema(botID: id, pluginID: pluginID)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
