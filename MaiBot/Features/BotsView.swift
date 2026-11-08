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
    @State private var updatedAt = Date()

    @State private var newName = ""
    @State private var renaming: Bot?
    @State private var cloning: Bot?
    @State private var deleting: Bot?
    @State private var textDraft = ""

    private var runningCount: Int { bots.filter(\.isRunning).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                statsCard
                newBotCard
                instancesHeader
                ForEach(bots) { bot in row(bot) }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(p.bg)
        .refreshable { await load() }
        .task { await load() }
        .alert("重命名 Bot", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名称", text: $textDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { if let b = renaming { Task { await rename(b) } } }
        }
        .alert("克隆 Bot", isPresented: Binding(get: { cloning != nil }, set: { if !$0 { cloning = nil } })) {
            TextField("新实例名称", text: $textDraft)
            Button("取消", role: .cancel) {}
            Button("克隆") { if let b = cloning { Task { await clone(b) } } }
        }
        .confirmationDialog("删除后不可恢复", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let b = deleting { Task { await remove(b) } } }
            Button("取消", role: .cancel) {}
        } message: { Text(deleting?.name ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack").font(.system(size: 22, weight: .medium)).foregroundStyle(p.text)
                Text("机器人管理").font(.system(size: 30, weight: .black)).foregroundStyle(p.text)
                if let name = bots.first(where: { $0.botID == selectedID })?.name ?? bots.first?.name {
                    HStack(spacing: 6) {
                        Circle().fill(p.green).frame(width: 7, height: 7)
                        Text("当前 Bot: \(name)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0x16A34A))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: 0xDCFCE7), in: .capsule)
                }
            }
            HStack {
                Text("每个 Bot 独立运行，共用一个管理入口。").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                Spacer()
                NavigationLink(value: ManageRoute.settings) {
                    Image(systemName: "gearshape").font(.system(size: 16)).foregroundStyle(p.text)
                        .frame(width: 38, height: 38)
                        .background(p.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.separator) }
                }
                .buttonStyle(.plain)
                Button { Task { await load() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        Text("刷新").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(p.text)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.separator) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("机器人数量统计").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                HStack(spacing: 0) {
                    statCol("全部 Bot", "\(bots.count)", p.text)
                    rectDivider(34)
                    statCol("运行中", "\(runningCount)", p.orange, dot: p.green)
                    rectDivider(34)
                    statCol("需要处理", "\(bots.count - runningCount)", p.text, dot: p.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.separator)
                        Capsule().fill(p.green).frame(width: geo.size.width * (bots.isEmpty ? 0 : Double(runningCount) / Double(bots.count)))
                    }
                }
                .frame(height: 7)
                Text("“运行中”只表示 Bot 进程存活，不代表账号已登录或模型、适配器已就绪。")
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary)
            }
        }
    }

    private func rectDivider(_ h: CGFloat) -> some View {
        Rectangle().fill(p.separator).frame(width: 1, height: h)
    }

    private func statCol(_ label: String, _ value: String, _ color: Color, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label).font(.system(size: 13)).foregroundStyle(p.textSecondary)
            }
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }

    private var newBotCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("新建 Bot").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                Text("创建独立配置和数据目录；创建后不会自动启动或登录。")
                    .font(.system(size: 13)).foregroundStyle(p.textSecondary)
                TextField("例如：工作助手", text: $newName)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.separator) }
                Button { Task { await create() } } label: {
                    HStack {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        Text("新建").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(hex: 0x9CA3AF) : p.text,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || busyID != nil)
            }
        }
    }

    private var instancesHeader: some View {
        HStack(spacing: 8) {
            Text("INSTANCES").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(p.textSecondary).tracking(1.5)
            Text("受管 Bot").font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
            Text("\(bots.count)").font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(p.separator) }
            Spacer()
            Text("更新于 " + timeText).font(.system(size: 12)).foregroundStyle(p.textTertiary)
        }
        .padding(.top, 6)
    }

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: updatedAt)
    }

    private func row(_ bot: Bot) -> some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(bot.isRunning ? p.green : p.textTertiary).frame(width: 8, height: 8)
                    Text("BOT-01").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(p.textSecondary)
                    Text(bot.name).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                    Text(bot.statusLabel).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(bot.isRunning ? Color(hex: 0x16A34A) : p.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(bot.isRunning ? Color(hex: 0xDCFCE7) : p.iconCircle, in: .capsule)
                    Spacer()
                    if selectedID == bot.botID {
                        Text("当前").font(.system(size: 12, weight: .medium)).foregroundStyle(p.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }
                    }
                    Menu {
                        Button { renaming = bot; textDraft = bot.name } label: { Label("重命名", systemImage: "pencil") }
                        Button { cloning = bot; textDraft = bot.name + " 副本" } label: { Label("克隆", systemImage: "doc.on.doc") }
                        if selectedID != bot.botID {
                            Button { Task { await select(bot) } } label: { Label("设为当前", systemImage: "checkmark.circle") }
                        }
                        Divider()
                        Button(role: .destructive) { deleting = bot } label: { Label("删除", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(p.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                }

                HStack(spacing: 0) {
                    infoCol("进程 ID", bot.pid.map(String.init) ?? "—")
                    rectDivider(30)
                    infoCol("退出码", bot.exitCode.map(String.init) ?? "—")
                    rectDivider(30)
                    infoCol("GATEWAY", "/main/" + String(bot.botID.prefix(6)) + "…", tint: p.orange)
                }
                .padding(.vertical, 10)
                .background(p.iconCircle.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    actionBtn("启动", "play", p.text) { await act(bot, .start) }
                    actionBtn("停止", "stop", p.text) { await act(bot, .stop) }
                    actionBtn("重启", "arrow.clockwise", p.text) { await act(bot, .restart) }
                    Spacer()
                }
            }
        }
        .opacity(busyID == bot.botID ? 0.6 : 1)
    }

    private func infoCol(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(p.textSecondary)
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(tint ?? p.text).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }

    private func actionBtn(_ title: String, _ icon: String, _ color: Color, run: @escaping () async -> Void) -> some View {
        Button { Task { await run() } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(p.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(p.separator) }
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
    }

    // MARK: - Actions

    private func load() async {
        do {
            let mode = try await client.hostMode()
            selectedID = mode.selectedBotID
            bots = try await client.bots()
            updatedAt = Date()
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }

    private func act(_ bot: Bot, _ action: BotAction) async {
        busyID = bot.botID
        defer { busyID = nil }
        do {
            try await client.setBotState(bot.botID, action: action)
            try? await Task.sleep(for: .milliseconds(800))
            await load()
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }

    private func select(_ bot: Bot) async {
        do { try await client.selectBot(bot.botID); selectedID = bot.botID }
        catch { self.error = error.localizedDescription }
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busyID = "create"
        defer { busyID = nil }
        do { try await client.createBot(name: name); newName = ""; await load() }
        catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }

    private func rename(_ bot: Bot) async {
        let name = textDraft.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty else { return }
        do { try await client.renameBot(bot.botID, name: name); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func clone(_ bot: Bot) async {
        let name = textDraft.trimmingCharacters(in: .whitespaces)
        cloning = nil
        guard !name.isEmpty else { return }
        do { try await client.cloneBot(bot.botID, name: name); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ bot: Bot) async {
        deleting = nil
        do { try await client.deleteBot(bot.botID); await load() }
        catch { self.error = error.localizedDescription }
    }
}