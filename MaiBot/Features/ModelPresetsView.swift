import SwiftUI

struct ModelPresetsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var tasks: [(String, [String])] = []
    @State private var models: [String] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                Text("任务 → 模型（\(tasks.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                ForEach(tasks, id: \.0) { pair in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pair.0).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(p.text)
                            Text(pair.1.isEmpty ? "（未配置）" : pair.1.joined(separator: " → "))
                                .font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(3)
                        }
                    }
                }
                if !models.isEmpty {
                    Text("模型（\(models.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(.top, 6)
                    Panel(padding: 14) {
                        Text(models.joined(separator: "、")).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    }
                }
                Text("只读：切换模型请用网页版或「模型列表」页。")
                    .font(.system(size: 11)).foregroundStyle(p.textTertiary).padding(.top, 4)
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("模型预设")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.configModel(botID: id)
            let root = (raw as? [String: Any])?["config"] as? [String: Any] ?? [:]
            let mtc = root["model_task_config"] as? [String: Any] ?? [:]
            tasks = mtc.map { (k, v) in
                let list = ((v as? [String: Any])?["model_list"] as? [String]) ?? []
                return (k, list)
            }.sorted { $0.0 < $1.0 }
            if let ms = root["models"] as? [String: Any] {
                models = ms.keys.sorted()
            } else if let ms = root["models"] as? [Any] {
                models = ms.map { "\($0)" }
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
