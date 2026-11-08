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

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                if items.isEmpty {
                    Text("暂无活动").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(items) { it in
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