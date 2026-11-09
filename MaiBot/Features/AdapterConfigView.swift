import SwiftUI

struct AdapterConfigView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var content: String?
    @State private var path: String?
    @State private var error: String?
    @State private var loading = true
    @State private var pathDraft = ""
    @State private var editingPath = false
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let e = error {
                    ErrorBanner(message: e) { Task { await load() } }
                } else if let path {
                    HStack {
                        Text(path).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(2)
                        Spacer()
                        Button("修改路径") { pathDraft = path; editingPath = true }
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(p.orange)
                    }
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
                    Text("填入 bot 目录下的适配器配置文件相对路径（如 data/adapter_config.toml）。")
                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                    if let u = URL(string: "/adapter-management", relativeTo: client.baseURL) {
                        Link("在网页版打开", destination: u).font(.system(size: 12)).foregroundStyle(p.orange)
                    }
                }
                if editingPath || (path == nil && error == nil && !loading) {
                    HStack(spacing: 8) {
                        TextField("配置文件路径", text: $pathDraft)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10)
                            .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(p.separator) }
                        Button(saving ? "保存中…" : "保存") { Task { await savePath() } }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(p.orange, in: Capsule())
                            .disabled(saving || pathDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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

    private func savePath() async {
        saving = true; defer { saving = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            _ = try await client.saveAdapterConfigPath(botID: id, path: pathDraft.trimmingCharacters(in: .whitespaces))
            editingPath = false
            await load()
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
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
