import SwiftUI

struct DataTransferView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var settings: [String: Any] = [:]
    @State private var items: [[String: Any]] = []
    @State private var error: String?
    @State private var loading = true

    private let limitKeys: [(String, String)] = [
        ("max_queue_size", "队列上限"), ("max_files_per_task", "每任务文件数"),
        ("max_file_size_mb", "单文件上限(MB)"), ("max_paste_chars", "粘贴字符上限"),
        ("default_file_concurrency", "文件并发"), ("default_chunk_concurrency", "分块并发")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                Text("导入任务（\(items.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                if items.isEmpty && !loading {
                    Text("暂无导入任务").font(.system(size: 13)).foregroundStyle(p.textSecondary).padding(.vertical, 10)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text((it["name"] as? String) ?? (it["id"] as? String) ?? "任务").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                            Text("状态：" + ((it["status"] as? String) ?? "—")).font(.system(size: 11)).foregroundStyle(p.textSecondary)
                        }
                    }
                }
                Text("导入参数（只读）").font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(.top, 8)
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(limitKeys, id: \.0) { pair in
                            HStack {
                                Text(pair.1).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                                Spacer()
                                Text(value(pair.0)).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.text)
                            }
                        }
                    }
                }
                Text("在网页版「数据迁移」上传文件或粘贴文本以创建导入任务。")
                    .font(.system(size: 11)).foregroundStyle(p.textTertiary)
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome("数据迁移")
        .refreshable { await load() }
        .task { await load() }
    }

    private func value(_ k: String) -> String {
        if let n = settings[k] as? NSNumber { return n.stringValue }
        if let s = settings[k] as? String { return s }
        return "—"
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.importTasks(botID: id)
            let d = raw as? [String: Any] ?? [:]
            settings = d["settings"] as? [String: Any] ?? [:]
            items = d["items"] as? [[String: Any]] ?? []
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
