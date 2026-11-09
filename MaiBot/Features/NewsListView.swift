import SwiftUI

struct NewsListView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [NewsResponse.NewsItem] = []
    @State private var error: String?
    @State private var selected: NewsResponse.NewsItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if items.isEmpty {
                    Text("暂无资讯").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(items) { item in
                    Button { selected = item } label: {
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                            if let s = item.summary, !s.isEmpty {
                                Text(s).font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(3)
                            }
                            HStack {
                                Text(item.source ?? "麦麦官方").font(.system(size: 11)).foregroundStyle(p.textTertiary)
                                Spacer()
                                if let t = item.publishedAt { Text(shortDate(t)).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary).lineLimit(1) }
                            }
                        }
                    }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .pageChrome("资讯")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.system(size: 20, weight: .bold)).foregroundStyle(p.text)
                        HStack {
                            Text(item.source ?? "麦麦官方").font(.system(size: 11)).foregroundStyle(p.textTertiary)
                            Spacer()
                            if let t = item.publishedAt { Text(shortDate(t)).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.textTertiary) }
                        }
                        Text(item.content ?? item.summary ?? "").font(.system(size: 14)).foregroundStyle(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(16)
                }
                .background(p.bg)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selected = nil } } }
            }
        }
    }

    private func shortDate(_ s: String) -> String {
        if let d = ISO8601.date(from: s) {
            let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
        }
        return s
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            items = try await client.news(botID: id)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
