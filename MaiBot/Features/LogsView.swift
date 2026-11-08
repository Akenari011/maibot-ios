//
//  LogsView.swift
//  MaiBot
//

import SwiftUI

struct LogsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var bots: [Bot] = []
    @State private var botID: String?
    @State private var text: String = ""
    @State private var error: String?
    @State private var autoRefresh = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker

                if let error {
                    ErrorBanner(message: error) { Task { await refresh() } }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                logPane
            }
            .background(p.background)
            .navigationTitle("日志")
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        autoRefresh.toggle()
                    } label: {
                        Image(systemName: autoRefresh ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                            .foregroundStyle(autoRefresh ? p.accent : p.textDim)
                    }
                    .buttonStyle(.glass)

                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .buttonStyle(.glass)
                }
            }
            .task {
                await loadBots()
                await refresh()
            }
            .task(id: autoRefresh) {
                guard autoRefresh else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    if Task.isCancelled { break }
                    await refresh()
                }
            }
        }
    }

    private var picker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(bots) { bot in
                    let active = botID == bot.botID
                    Button {
                        botID = bot.botID
                        text = ""
                        Task { await refresh() }
                    } label: {
                        Text(bot.name)
                            .font(.system(size: 13, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? p.accent : p.textDim)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                (active ? p.accent : p.surfaceRaised).opacity(active ? 0.15 : 0.6),
                                in: .capsule
                            )
                            .overlay {
                                Capsule().strokeBorder(
                                    active ? p.accent.opacity(0.5) : p.border,
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "（暂无日志）" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? p.textMute : p.textDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .id("bottom")
            }
            .background(p.surface.opacity(p.isDark ? 0.5 : 1), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(p.border, lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Data

    private func loadBots() async {
        do {
            bots = try await client.bots()
            if botID == nil { botID = bots.first?.botID }
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        guard let botID else { return }
        do {
            let body = try await client.logs(botID: botID, limit: 500)
            text = body
            error = nil
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
