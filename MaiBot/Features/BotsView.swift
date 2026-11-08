//
//  BotsView.swift
//  MaiBot
//

import SwiftUI

struct BotsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var bots: [Bot] = []
    @State private var selectedID: String?
    @State private var error: String?
    @State private var busyID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    }

                    if bots.isEmpty {
                        ContentUnavailableView {
                            Label("没有机器人", systemImage: "cpu")
                        } description: {
                            Text("在网页版中添加一个机器人实例")
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(bots) { bot in
                            row(bot)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(p.background)
            .navigationTitle("机器人")
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await load() }
        }
    }

    private func row(_ bot: Bot) -> some View {
        Panel {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((bot.isRunning ? p.accent : p.textMute).opacity(0.14))
                        Image(systemName: "cpu")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(bot.isRunning ? p.accent : p.textMute)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(bot.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(p.text)
                            if selectedID == bot.botID {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.accent)
                            }
                        }
                        Text(bot.uptimeText ?? bot.statusLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(p.textDim)
                    }

                    Spacer()
                    StatusPill(text: bot.statusLabel, tone: bot.statusTone)
                }

                Divider().overlay(p.border)

                HStack(spacing: 8) {
                    compactAction(bot, .start, "启动", "play.fill", p.accent)
                    compactAction(bot, .restart, "重启", "arrow.triangle.2.circlepath", p.amber)
                    compactAction(bot, .stop, "停止", "stop.fill", p.danger)

                    Spacer()

                    Button {
                        Task { await select(bot) }
                    } label: {
                        Image(systemName: selectedID == bot.botID ? "checkmark" : "arrow.right.circle")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.glass)
                    .disabled(selectedID == bot.botID)
                }
            }
        }
    }

    private func compactAction(_ bot: Bot, _ action: BotAction, _ title: String, _ icon: String, _ tint: Color) -> some View {
        Button {
            Task { await perform(bot, action) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint.opacity(0.13), in: .capsule)
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .opacity(busyID == bot.botID ? 0.55 : 1)
    }

    // MARK: - Data

    private func load() async {
        do {
            let m = try await client.hostMode()
            selectedID = m.selectedBotID
            bots = try await client.bots()
            error = nil
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func perform(_ bot: Bot, _ action: BotAction) async {
        busyID = bot.botID
        defer { busyID = nil }
        do {
            try await client.setBotState(bot.botID, action: action)
            try? await Task.sleep(for: .milliseconds(700))
            await load()
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func select(_ bot: Bot) async {
        do {
            try await client.selectBot(bot.botID)
            selectedID = bot.botID
        } catch {
            self.error = error.localizedDescription
        }
    }
}
