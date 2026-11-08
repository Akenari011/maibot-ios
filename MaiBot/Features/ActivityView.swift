//
//  ActivityView.swift
//  MaiBot
//

import SwiftUI

struct ActivityView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var items: [Dashboard.ActivityItem] = []
    @State private var error: String?
    @State private var query = ""

    private var filtered: [Dashboard.ActivityItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            ($0.model ?? "").localizedCaseInsensitiveContains(q) ||
            ($0.requestType ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    TextField("搜索模型 / 类型…", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 12).frame(height: 38).background(p.iconCircle, in: RoundedRectangle(cornerRadius: 10))
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                Text("共 \(filtered.count) 条 · 合计 " + fmtToken(items.reduce(0) { $0 + ($1.tokens ?? 0) }) + " tok")
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                if filtered.isEmpty {
                    Text("暂无活动").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(filtered) { it in
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(it.clock).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(p.text)
                                Text(it.model ?? "—").font(.system(size: 13)).foregroundStyle(p.textSecondary).lineLimit(1)
                                Spacer()
                                Text(fmtToken(it.tokens ?? 0) + " tok").font(.system(size: 12)).foregroundStyle(p.orange)
                            }
                            HStack {
                                Text(it.requestType ?? "").font(.system(size: 11)).foregroundStyle(p.textTertiary).lineLimit(1)
                                Spacer()
                                if let t = it.timeCost { Text(String(format: "%.2fs", t)).font(.system(size: 11)).foregroundStyle(p.textTertiary) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .navigationTitle("活动流")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let d = try await client.dashboard(botID: id, hours: 24)
            items = d.recentActivity ?? []
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}