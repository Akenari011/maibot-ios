import SwiftUI

struct StageRow: Identifiable {
    let id: String
    let sessions: Int
    let latest: Double?
}

struct ReasonFileRow: Identifiable {
    let id: String
    let stage: String
    let session: String
    let ts: Double
}

struct ReasoningView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var tab = 0
    @State private var stages: [StageRow] = []
    @State private var files: [ReasonFileRow] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("视图", selection: $tab) {
                    Text("提示词阶段").tag(0)
                    Text("文件").tag(1)
                }.pickerStyle(.segmented)
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if tab == 0 {
                    Text("阶段（\(stages.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    ForEach(stages) { s in
                        Panel(padding: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.id).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(p.text).lineLimit(1)
                                    Text("\(s.sessions) 个会话" + (s.latest.map { " · 最近 " + fmtTime($0) } ?? ""))
                                        .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                                }
                                Spacer()
                            }
                        }
                    }
                } else {
                    Text("推理文件（\(files.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    ForEach(files) { f in
                        Panel(padding: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(f.stage).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(p.text).lineLimit(1)
                                    Spacer()
                                    Text(fmtTime(f.ts)).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textTertiary)
                                }
                                Text(f.session.isEmpty ? "—" : f.session).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("推理过程")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func fmtTime(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts > 1e12 ? ts / 1000 : ts)
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let s = try await client.reasoningStages(botID: id) as? [String: Any] ?? [:]
            let infos = s["stage_infos"] as? [[String: Any]] ?? []
            stages = infos.map { m in
                StageRow(id: (m["name"] as? String) ?? "—",
                         sessions: (m["session_count"] as? Int) ?? Int((m["session_count"] as? Double) ?? 0),
                         latest: (m["latest_modified_at"] as? Double))
            }.sorted { $0.id < $1.id }
            let fr = try await client.reasoningFiles(botID: id) as? [String: Any] ?? [:]
            let items = fr["items"] as? [[String: Any]] ?? []
            files = items.map { m in
                ReasonFileRow(id: ((m["json_path"] as? String) ?? UUID().uuidString),
                              stage: (m["stage"] as? String) ?? "—",
                              session: (m["session_display_name"] as? String) ?? "",
                              ts: (m["timestamp"] as? Double) ?? 0)
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
