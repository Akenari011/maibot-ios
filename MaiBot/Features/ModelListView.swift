//
//  ModelListView.swift
//  MaiBot
//

import SwiftUI

struct ModelListView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var models: [ModelConfig.ModelInfo] = []
    @State private var query = ""
    @State private var error: String?

    private var filtered: [ModelConfig.ModelInfo] {
        query.isEmpty ? models : models.filter {
            $0.modelIdentifier.localizedCaseInsensitiveContains(query) ||
            ($0.apiProvider ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(p.textTertiary)
                    TextField("搜索模型…", text: $query).font(.system(size: 15))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(p.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.separator) }

                if let error { ErrorBanner(message: error) { Task { await load() } } }

                ForEach(filtered) { m in
                    Panel(padding: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(p.iconCircle).frame(width: 40, height: 40)
                                Image(systemName: (m.visual ?? false) ? "eye" : "cpu")
                                    .font(.system(size: 15)).foregroundStyle(p.text)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                                Text(m.apiProvider ?? "—").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                            }
                            Spacer()
                            Text(m.modelType ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(p.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(p.iconCircle, in: .capsule)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .navigationTitle("模型列表")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            models = try await client.models(botID: id)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}