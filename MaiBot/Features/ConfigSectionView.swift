import SwiftUI

struct ConfigSectionView: View {
    let section: String
    let title: String
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var value: Any?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if let value { JSONValueView(key: section, value: value) }
                Text("只读：编辑请在网页版操作。")
                    .font(.system(size: 11)).foregroundStyle(p.textTertiary).padding(.top, 6)
            }
            .padding(16)
        }
        .background(p.bg)
        .pageChrome(title)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.configBot(botID: id)
            let root = (raw as? [String: Any])?["config"] as? [String: Any] ?? [:]
            value = root[section]
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
