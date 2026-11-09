import SwiftUI

struct GraphNodeRow: Identifiable {
    let id: String
    let name: String
    let detail: String
}

struct GraphEdgeRow: Identifiable {
    let id: String
    let source: String
    let target: String
    let label: String
    let weight: Double
}

struct KnowledgeGraphView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p
    @State private var tab = 0
    @State private var nodes: [GraphNodeRow] = []
    @State private var edges: [GraphEdgeRow] = []
    @State private var totalNodes = 0
    @State private var totalEdges = 0
    @State private var query = ""
    @State private var error: String?
    @State private var loading = true

    private var filteredNodes: [GraphNodeRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? nodes : nodes.filter { $0.name.lowercased().contains(q) }
    }
    private var filteredEdges: [GraphEdgeRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? edges : edges.filter {
            $0.source.lowercased().contains(q) || $0.target.lowercased().contains(q) || $0.label.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("视图", selection: $tab) {
                    Text("节点 \(totalNodes)").tag(0)
                    Text("关系 \(totalEdges)").tag(1)
                }.pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索节点/关系…", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 20) }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if tab == 0 {
                    ForEach(filteredNodes) { n in
                        Panel(padding: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                if !n.detail.isEmpty { Text(n.detail).font(.system(size: 11)).foregroundStyle(p.textSecondary).lineLimit(1) }
                            }
                        }
                    }
                } else {
                    ForEach(filteredEdges) { e in
                        Panel(padding: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.source + " → " + e.target).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                Text(e.label + " · 权重 " + String(format: "%.1f", e.weight))
                                    .font(.system(size: 11)).foregroundStyle(p.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
                Text("仅展示前 500 个节点/关系；完整图谱请在网页版查看。")
                    .font(.system(size: 10)).foregroundStyle(p.textTertiary).padding(.top, 4)
            }
            .padding(16)
        }
        .background(p.bg)
        .navigationTitle("知识图谱")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let raw = try await client.memoryGraph(botID: id)
            let d = raw as? [String: Any] ?? [:]
            totalNodes = (d["total_nodes"] as? Int) ?? 0
            totalEdges = (d["total_edges"] as? Int) ?? 0
            let ns = d["nodes"] as? [[String: Any]] ?? []
            nodes = ns.map { m in
                let attrs = m["attributes"] as? [String: Any] ?? [:]
                let detail = attrs.isEmpty ? "" : attrs.map { "\($0.key)=\($0.value)" }.joined(separator: " · ")
                return GraphNodeRow(id: (m["id"] as? String) ?? UUID().uuidString,
                                    name: (m["name"] as? String) ?? "—",
                                    detail: detail)
            }
            let es = d["edges"] as? [[String: Any]] ?? []
            edges = es.map { m in
                GraphEdgeRow(id: ((m["source"] as? String) ?? "") + "→" + ((m["target"] as? String) ?? "") + ((m["label"] as? String) ?? ""),
                             source: (m["source"] as? String) ?? "—",
                             target: (m["target"] as? String) ?? "—",
                             label: (m["label"] as? String) ?? "",
                             weight: (m["weight"] as? Double) ?? 1)
            }
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
