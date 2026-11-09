import SwiftUI

struct FileRow: Identifiable {
    let id: String
    let name: String
    let size: Double
    let mime: String
    let state: String
}

struct FilesView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var items: [FileRow] = []
    @State private var error: String?
    @State private var search = ""
    @State private var selected: FileRow?
    @State private var preview: String?
    @State private var previewLoading = false

    private var filtered: [FileRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? items : items.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索文件…", text: $search).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                Text("文件（\(filtered.count)）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if filtered.isEmpty { Text("暂无文件").font(.system(size: 13)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity).padding(.top, 30) }
                ForEach(filtered) { f in
                    Button { Task { await open(f) } } label: {
                    Panel(padding: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc").font(.system(size: 16)).foregroundStyle(p.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.name).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text).lineLimit(1)
                                Text(f.mime + (f.state.isEmpty ? "" : " · " + f.state)).font(.system(size: 11)).foregroundStyle(p.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Text(fmtSize(f.size)).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.textSecondary)
                        }
                    }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .pageChrome("数据传输")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { f in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(f.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                        if previewLoading { ProgressView() }
                        if let preview {
                            Text(preview).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textSecondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        } else if !previewLoading {
                            Text("无法预览（非文本文件或读取失败）").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                        }
                    }.padding(16)
                }
                .background(p.bg)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selected = nil } } }
            }
        }
    }

    private func open(_ f: FileRow) async {
        selected = f; preview = nil; previewLoading = true; defer { previewLoading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            preview = try await client.fileText(botID: id, ref: f.id)
        } catch { preview = nil }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.files(botID: id)
            let list = (raw as? [String: Any])?["items"] as? [[String: Any]] ?? []
            items = list.map { m in
                FileRow(id: (m["file_ref"] as? String) ?? UUID().uuidString,
                        name: (m["name"] as? String) ?? "—",
                        size: (m["size"] as? Double) ?? Double((m["size"] as? Int) ?? 0),
                        mime: (m["mime_type"] as? String) ?? "",
                        state: (m["state"] as? String) ?? "")
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
