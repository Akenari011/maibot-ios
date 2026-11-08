import SwiftUI

struct NewsListView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [NewsResponse.NewsItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let e = error { Text(e).font(.system(size: 13)).foregroundStyle(.red) }
                if items.isEmpty {
                    Text("暂无资讯").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(items) { item in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                            if let s = item.summary, !s.isEmpty {
                                Text(s).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(3)
                            }
                            HStack {
                                Text(item.source ?? "麦麦官方").font(.system(size: 11)).foregroundStyle(p.textTertiary)
                                Spacer()
                                if let t = item.publishedAt { Text(t).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(1) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .navigationTitle("资讯")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            items = try await client.news(botID: id).items
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
