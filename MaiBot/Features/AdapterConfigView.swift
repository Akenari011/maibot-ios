import SwiftUI

struct AdapterConfigView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var content: String?
    @State private var path: String?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let e = error {
                    ErrorBanner(message: e) { Task { await load() } }
                } else if let path {
                    Text(path).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                    if let content {
                        Text(content)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("配置文件内容为空").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    }
                } else {
                    Text("尚未设置适配器配置文件路径").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                    Text("请先在网页版「适配器设置」中选择配置文件，然后回到此页刷新。")
                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("适配器设置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.adapterConfigPath(botID: id)
            guard let pth = (raw as? [String: Any])?["path"] as? String, !pth.isEmpty else {
                path = nil; content = nil; error = nil; return
            }
            path = pth
            let cfg = try await client.adapterConfig(botID: id, path: pth)
            content = (cfg as? [String: Any])?["content"] as? String
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
