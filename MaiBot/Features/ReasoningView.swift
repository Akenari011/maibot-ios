import SwiftUI

struct ReasoningView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var tab = 0
    @State private var stages: Any?
    @State private var files: Any?
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
                if tab == 0, let v = stages { JSONValueView(key: nil, value: v) }
                if tab == 1, let v = files { JSONValueView(key: nil, value: v) }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("推理过程")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            stages = try await client.reasoningStages(botID: id)
            files = try await client.reasoningFiles(botID: id)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
