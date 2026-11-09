import SwiftUI

struct ComputerView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var status: Any?
    @State private var frame: UIImage?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if let status {
                    Panel(padding: 12) { JSONValueView(key: nil, value: status) }
                }
                if let frame {
                    Image(uiImage: frame).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(p.separator) }
                } else if !loading {
                    Text("暂无画面").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Text("只读：桌面控制请在网页版操作。").font(.system(size: 11)).foregroundStyle(p.textTertiary)
            }.padding(16)
        }
        .background(p.bg)
        .pageChrome("电脑使用")
        .refreshable { await load() }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                await refreshFrame()
            }
        }
    }

    private func refreshFrame() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            if let d = try? await client.computerFrame(botID: id), let img = UIImage(data: d) { frame = img }
        } catch {}
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            status = try? await client.computerStatus(botID: id)
            if let d = try? await client.computerFrame(botID: id) { frame = UIImage(data: d) }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
