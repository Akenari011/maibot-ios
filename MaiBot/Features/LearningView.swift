import SwiftUI

struct LearnedRow: Identifiable {
    let id = UUID()
    let title: String
    let desc: String
    let evidence: String
}

struct LearningView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var kind = "expression"
    @State private var text = ""
    @State private var rows: [LearnedRow] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("类型", selection: $kind) {
                    Text("表达风格").tag("expression")
                    Text("黑话").tag("jargon")
                }.pickerStyle(.segmented)
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.separator) }
                Button {
                    Task { await run() }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "抽取中…" : "抽取候选").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(p.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let e = error { ErrorBanner(message: e) { Task { await run() } } }
                ForEach(rows) { r in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                            Text(r.desc).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                            if !r.evidence.isEmpty {
                                Text("依据：" + r.evidence).font(.system(size: 11)).foregroundStyle(p.textTertiary).lineLimit(3)
                            }
                        }
                    }
                }
                if rows.isEmpty && !busy && error == nil {
                    Text("粘贴一段聊天记录，抽取可学习的表达/黑话候选。")
                        .font(.system(size: 11)).foregroundStyle(p.textTertiary)
                }
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("学习")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        busy = true; defer { busy = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.learnText(botID: id, kind: kind, text: text)
            let list = (raw as? [String: Any])?["candidates"] as? [[String: Any]] ?? []
            rows = list.map {
                LearnedRow(title: ($0["title"] as? String) ?? "—",
                           desc: ($0["description"] as? String) ?? "",
                           evidence: ($0["evidence"] as? String) ?? "")
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
