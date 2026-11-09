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
    @State private var testResult: String?
    @State private var testing = false
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

                if filtered.isEmpty {
                    Text(query.isEmpty ? "暂无模型" : "没有匹配的模型")
                        .font(.system(size: 13)).foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }

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
                            Button(testing ? "…" : "测试") {
                                Task { await test(m.apiProvider ?? "") }
                            }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(p.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(p.orange.opacity(0.12), in: .capsule)
                            .disabled(testing || (m.apiProvider ?? "").isEmpty)
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
        .alert("测试结果", isPresented: Binding(get: { testResult != nil }, set: { if !$0 { testResult = nil } })) {
            Button("好") { testResult = nil }
        } message: { Text(testResult ?? "") }
        .task { await load() }
    }

    private func test(_ provider: String) async {
        guard !provider.isEmpty else { return }
        testing = true; defer { testing = false }
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            let r = try await client.testProvider(botID: id, name: provider)
            let d = r as? [String: Any] ?? [:]
            let ok = (d["network_ok"] as? Bool) ?? false
            let latency = d["latency_ms"].map { "\($0)" } ?? "—"
            let err = (d["error"] as? String) ?? ""
            testResult = (ok ? "✅ 连接成功" : "❌ 连接失败") + "\n延迟: " + latency + " ms" + (err.isEmpty ? "" : "\n" + err)
        } catch { testResult = "❌ " + error.localizedDescription }
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