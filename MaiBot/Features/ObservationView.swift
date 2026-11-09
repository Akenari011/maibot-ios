import SwiftUI

struct ObservationView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var dash: Dashboard?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.system(size: 26, weight: .bold)).foregroundStyle(p.text)
                    Text("麦麦的观察").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if let d = dash {
                    Panel {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                            stat("总请求", fmtCount(d.summary.totalRequests))
                            stat("总花费", "¥" + String(format: "%.2f", d.summary.totalCost))
                            stat("Token", fmtToken(d.summary.totalTokens))
                            stat("平均响应", String(format: "%.2fs", d.summary.avgResponseTime))
                        }
                    }
                    if let acts = d.recentActivity, !acts.isEmpty {
                        Text("最近活动").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                        ForEach(acts.prefix(20)) { a in
                            Panel(padding: 12) {
                                HStack {
                                    Text(a.clock).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(p.text)
                                    Text(a.model ?? "—").font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(1)
                                    Spacer()
                                    Text(fmtToken(a.tokens ?? 0) + " tok").font(.system(size: 11)).foregroundStyle(p.orange)
                                }
                            }
                        }
                    }
                }
                Text("『生活明朗，万物可爱。』 — 麦麦一言").font(.system(size: 12)).italic().foregroundStyle(p.textSecondary)
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("观察")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 6 { return "夜深了" }
        if h < 12 { return "早上好" }
        if h < 18 { return "下午好" }
        return "晚上好"
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 11)).foregroundStyle(p.textSecondary)
            Text(v).font(.system(size: 20, weight: .semibold)).foregroundStyle(p.text)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            dash = try await client.dashboard(botID: id, hours: 24)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
