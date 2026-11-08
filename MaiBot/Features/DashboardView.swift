//
//  DashboardView.swift
//  MaiBot
//

import SwiftUI

struct DashboardView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var mode: HostMode?
    @State private var bots: [Bot] = []
    @State private var error: String?
    @State private var busy = false
    @State private var appeared = false

    private var selectedBot: Bot? {
        guard let id = mode?.selectedBotID else { return bots.first }
        return bots.first { $0.botID == id }
    }

    private var runningCount: Int { bots.filter(\.isRunning).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    }

                    heroCard
                    statsRow
                    if let b = selectedBot { botCard(b) }
                    quickActions
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(p.background)
            .navigationTitle("概览")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(busy)
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    // MARK: - Sections

    private var heroCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("宿主状态")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.textMute)
                        Text(mode?.authenticated == true ? "已连接" : "连接中…")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(p.text)
                    }
                    Spacer()
                    StatusPill(
                        text: mode?.host == true ? "宿主模式" : "待机",
                        tone: mode?.host == true ? .ok : .idle
                    )
                }

                Divider().overlay(p.border)

                HStack(spacing: 0) {
                    metric("在线机器人", "\(runningCount)/\(bots.count)", p.accent)
                    Rectangle().fill(p.border).frame(width: 1, height: 30)
                    metric("当前选中", selectedBot?.name ?? "—", p.text)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(icon: "bolt.fill", label: "运行中", value: "\(runningCount)", tint: p.accent)
            statTile(icon: "pause.fill", label: "已停止", value: "\(bots.count - runningCount)", tint: p.textMute)
        }
    }

    private func botCard(_ b: Bot) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.name).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(p.text)
                        Text(b.directory ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.textMute)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    StatusPill(text: b.statusLabel, tone: b.statusTone)
                }

                Divider().overlay(p.border)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    infoCell("PID", b.pid.map(String.init) ?? "—")
                    infoCell("运行时长", b.uptimeText ?? "—")
                    infoCell("重启策略", b.restartPolicy ?? "—")
                    infoCell("初始化", b.initialization ?? "—")
                }

                if let err = b.error, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(p.danger)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.danger.opacity(0.1), in: .rect(cornerRadius: 8))
                }
            }
        }
    }

    private var quickActions: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("快捷操作")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.textMute)

                if let b = selectedBot {
                    HStack(spacing: 10) {
                        actionButton("启动", "play.fill", p.accent) {
                            await act(b, .start)
                        }
                        actionButton("重启", "arrow.triangle.2.circlepath", p.amber) {
                            await act(b, .restart)
                        }
                        actionButton("停止", "stop.fill", p.danger) {
                            await act(b, .stop)
                        }
                    }
                } else {
                    Text("没有可操作的机器人").font(.system(size: 13)).foregroundStyle(p.textDim)
                }
            }
        }
    }

    // MARK: - Pieces

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            Text(label).font(.system(size: 11)).foregroundStyle(p.textMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statTile(icon: String, label: String, value: String, tint: Color) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(p.text)
                Text(label).font(.system(size: 11)).foregroundStyle(p.textMute)
            }
        }
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(p.textMute)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(p.textDim)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ title: String, _ icon: String, _ tint: Color, run: @escaping () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.13), in: .rect(cornerRadius: 10))
            .foregroundStyle(tint)
        }
        .disabled(busy)
    }

    // MARK: - Data

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            async let m = client.hostMode()
            async let b = client.bots()
            mode = try await m
            bots = try await b
            error = nil
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
        withAnimation(.easeOut(duration: 0.3)) { appeared = true }
    }

    private func act(_ bot: Bot, _ action: BotAction) async {
        busy = true
        defer { busy = false }
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
}

// MARK: - Shared bits

struct ErrorBanner: View {
    @Environment(\.palette) private var p
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(p.danger)
            Text(message).font(.system(size: 13)).foregroundStyle(p.text)
                .lineLimit(3)
            Spacer()
            Button("重试", action: retry)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.accent)
        }
        .padding(12)
        .background(p.danger.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(p.danger.opacity(0.3), lineWidth: 1)
        }
    }
}
