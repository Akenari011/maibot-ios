//
//  DashboardView.swift
//  MaiBot
//
//  Home screen, laid out 1:1 with the panel: activity card, quick-action
//  grid, storage breakdown, statistics, charts, prompt cache, news.
//

import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var bot: Bot?
    @State private var dash: Dashboard?
    @State private var cache: LocalCache?
    @State private var news: [NewsResponse.NewsItem] = []
    @State private var error: String?
    @State private var range: Int = 24
    @State private var statusFlipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenChat: () -> Void = {}

    private var hourLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let error {
                    ErrorBanner(message: error) { Task { await load() } }
                }
                botStatusCard
                gridCard
                hitokotoLine
                if let cache { storageCard(cache) }
                if let dash { statsCard(dash.summary) }
                if let dash { trendCard(dash) }
                if let dash { tokenCard(dash) }
                if let dash { promptCard(dash.summary) }
                if !news.isEmpty { newsCard }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(p.bg)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hourLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(p.textSecondary)
                    Text("麦麦")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(p.text)
                }
                Spacer()
                NavigationLink(value: HomeRoute.settings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(p.text)
                        .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                Text("MAIBOT V1.4.0").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(p.text)
                Text("CONSOLE V1.10.0").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(p.text)
                Text("资讯").font(.system(size: 14)).foregroundStyle(p.orange)
                Text("麦麦支持…").font(.system(size: 14)).foregroundStyle(p.textSecondary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(p.textTertiary)
            }
        }
    }

    // MARK: activity

    private var botStatusCard: some View {
        Panel {
            ZStack {
                statusFront
                    .opacity(statusFlipped ? 0 : 1)
                statusBack
                    .opacity(statusFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(.degrees(statusFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.46), value: statusFlipped)
            .contentShape(.rect)
            .onTapGesture { statusFlipped.toggle() }
        }
    }

    private var statusFront: some View {
        let running = bot?.isRunning ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(running ? "运行中" : "已停止")
                    .font(.system(size: 34, weight: .semibold)).tracking(-0.6)
                    .foregroundStyle(p.text)
                if running { Circle().fill(p.green).frame(width: 8, height: 8) }
            }
            Text(bot?.uptimeText ?? "离线")
                .font(.system(size: 15)).foregroundStyle(p.textSecondary).padding(.top, 2)
            Divider().overlay(p.separator).padding(.vertical, 16)
            HStack(spacing: 0) {
                DotTag(text: "启用视觉")
                Spacer()
                DotTag(text: "启用记忆")
                Spacer()
            }
        }
    }

    private var statusBack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近在线").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary)
            if let d = dash {
                let pts = Array(d.hourlyData.suffix(24))
                let maxV = max(1, pts.map { $0.requests }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(pts) { pt in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(p.orange.opacity(0.68))
                            .frame(height: max(2, CGFloat(pt.requests / maxV) * 44))
                    }
                }
                .frame(height: 46)
                Text("近 24h 请求 " + fmtCount(pts.reduce(0) { $0 + $1.requests }))
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary)
            } else {
                Text("暂无数据").font(.system(size: 13)).foregroundStyle(p.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: quick grid

    private var gridCard: some View {
        Panel(padding: 18) {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("快捷操作").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                Spacer()
                NavigationLink(value: HomeRoute.settings) {
                    Text("自定义").font(.system(size: 13)).foregroundStyle(p.orange)
                }.buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 20) {
                NavigationLink(value: HomeRoute.logs) { GridTile(icon: "doc.text", label: "查看日志") }
                    .buttonStyle(.plain)
                NavigationLink(value: HomeRoute.settings) { GridTile(icon: "gearshape", label: "外观设置") }
                    .buttonStyle(.plain)
                NavigationLink(value: HomeRoute.models) { GridTile(icon: "cpu", label: "模型列表") }
                    .buttonStyle(.plain)
                Button { onOpenChat() } label: { GridTile(icon: "bubble.left", label: "麦麦聊聊") }
                    .buttonStyle(.plain)
                NavigationLink(value: HomeRoute.activity) { GridTile(icon: "doc.on.doc", label: "回复日志") }
                    .buttonStyle(.plain)
                NavigationLink(value: HomeRoute.activity) { GridTile(icon: "doc.text.magnifyingglass", label: "推理日志") }
                    .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
          }
        }
    }

    private var hitokotoLine: some View {
        let quotes: [(String, String)] = [
            ("生活明朗，万物可爱。", "— 麦麦一言"),
            ("慢慢来，比较快。", "— 麦麦一言"),
            ("把复杂留给我，把简单留给你。", "— 麦麦一言")
        ]
        let q = quotes[Calendar.current.component(.day, from: Date()) % quotes.count]
        return HStack(spacing: 6) {
            Text("『" + q.0 + "』").font(.system(size: 13)).italic().foregroundStyle(p.textSecondary)
            Text(q.1).font(.system(size: 12)).foregroundStyle(p.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: storage

    private func storageCard(_ c: LocalCache) -> some View {
        // image / emoji / logs dirs + database
        var rows: [(String, Double)] = []
        for d in c.directories {
            let label = d.key == "images" ? "图片" : (d.key == "emoji" ? "表情" : (d.key == "logs" ? "日志" : d.label))
            rows.append((label, d.totalSize))
        }
        rows.append(("数据库", c.database.totalSize))
        let total = rows.reduce(0) { $0 + $1.1 }
        return Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmtSize(total)).font(.system(size: 38, weight: .black)).foregroundStyle(p.text)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("大小").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                        Text("/").font(.system(size: 14)).foregroundStyle(p.textTertiary)
                        Text("数量").font(.system(size: 14)).foregroundStyle(p.textSecondary)
                    }
                }
                VStack(spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        StorageRow(label: r.0, value: fmtSize(r.1), fraction: total > 0 ? r.1 / total : 0)
                    }
                }
                NavigationLink(value: HomeRoute.files) {
                    HStack {
                        Spacer()
                        Text("管理存储").font(.system(size: 15, weight: .medium)).foregroundStyle(p.orange)
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium)).foregroundStyle(p.orange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: stats

    private func statsCard(_ s: Dashboard.Summary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("统计概览", systemImage: "chart.bar").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Spacer()
                    SegmentedChips(items: [24, 168, 720], label: { $0 == 24 ? "24小时" : ($0 == 168 ? "7天" : "30天") }, selection: $range)
                }
                HStack(alignment: .top, spacing: 24) {
                    primaryStat("总请求数", fmtCount(s.totalRequests))
                    primaryStat("总花费", "¥" + String(format: "%.2f", s.totalCost))
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 16) {
                    secondaryStat("Token消耗", fmtToken(s.totalTokens))
                    secondaryStat("平均响应", String(format: "%.2fs", s.avgResponseTime))
                    secondaryStat("在线时长", String(format: "%.1fh", s.onlineTime / 3600))
                    secondaryStat("消息", fmtCount(s.totalMessages))
                }
            }
        }
    }

    private func primaryStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(p.textSecondary)
            Text(value).font(.system(size: 28, weight: .semibold)).tracking(-0.4).foregroundStyle(p.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(p.textSecondary)
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(p.text)
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14)).foregroundStyle(p.textSecondary)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(p.text)
        }
    }

    // MARK: charts

    private func trendCard(_ d: Dashboard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("请求趋势", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Spacer()
                    SegmentedChips(items: [24, 168, 720], label: { $0 == 24 ? "24小时" : ($0 == 168 ? "7天" : "30天") }, selection: $range)
                }
                HStack(spacing: 6) {
                    Circle().fill(p.orange).frame(width: 7, height: 7)
                    Text("请求数").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Chart(d.hourlyData) { pt in
                    LineMark(x: .value("时间", pt.hourLabel), y: .value("请求", pt.requests))
                        .foregroundStyle(p.orange)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("时间", pt.hourLabel), y: .value("请求", pt.requests))
                        .foregroundStyle(p.orange.opacity(0.08))
                        .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { val in
                        AxisGridLine().foregroundStyle(p.separator)
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(p.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine().foregroundStyle(p.separator)
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(p.textTertiary)
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private func tokenCard(_ d: Dashboard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Token消耗", systemImage: "chart.bar.doc.horizontal").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Spacer()
                    SegmentedChips(items: [24, 168, 720], label: { $0 == 24 ? "24小时" : ($0 == 168 ? "7天" : "30天") }, selection: $range)
                }
                HStack(spacing: 14) {
                    HStack(spacing: 6) { Circle().fill(p.orange).frame(width: 7, height: 7); Text("输入 Token").font(.system(size: 12)).foregroundStyle(p.textSecondary) }
                    HStack(spacing: 6) { Circle().fill(Color(hex: 0x2FD6C4)).frame(width: 7, height: 7); Text("输出 Token").font(.system(size: 12)).foregroundStyle(p.textSecondary) }
                }
                Chart(d.hourlyData) { pt in
                    BarMark(x: .value("时间", pt.hourLabel), y: .value("Token", pt.inputTokens))
                        .foregroundStyle(p.orange)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { _ in
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(p.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(p.separator)
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(p.textTertiary)
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private func promptCard(_ s: Dashboard.Summary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Prompt缓存", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Spacer()
                    SegmentedChips(items: [24, 168, 720], label: { $0 == 24 ? "24小时" : ($0 == 168 ? "7天" : "30天") }, selection: $range)
                }
                HStack(spacing: 12) {
                    cacheTile("全部", s.cacheHitRate ?? 0)
                    cacheTile("聊天", s.chatCacheHitRate ?? 0)
                }
            }
        }
    }

    private func cacheTile(_ title: String, _ rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(p.textSecondary)
            Text(String(format: "%.2f%%", rate * 100)).font(.system(size: 26, weight: .bold)).foregroundStyle(p.text)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.separator)
                    Capsule().fill(p.text).frame(width: max(4, geo.size.width * min(max(rate, 0), 1)))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(p.separator, lineWidth: 1) }
    }

    // MARK: news

    private var newsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("资讯", systemImage: "newspaper").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Text("\(news.count)条未读").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(p.text, in: .capsule)
                    Spacer()
                }
                ForEach(news.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(p.text).frame(width: 4, height: 4)
                            Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                        }
                        Text(item.summary ?? "").font(.system(size: 12)).foregroundStyle(p.textSecondary).lineLimit(2)
                        HStack {
                            Text(item.source ?? "麦麦官方").font(.system(size: 11)).foregroundStyle(p.textTertiary)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                    if item.id != news.prefix(3).last?.id { Divider().overlay(p.separator) }
                }
            }
        }
    }

    // MARK: data

    private func load() async {
        do {
            let mode = try await client.hostMode()
            let list = try await client.bots()
            bot = list.first { $0.botID == mode.selectedBotID } ?? list.first
            if let b = bot {
                async let d = client.dashboard(botID: b.botID, hours: range)
                async let c = client.localCache(botID: b.botID)
                async let n = client.news(botID: b.botID)
                dash = try await d
                cache = try await c
                news = (try? await n) ?? []
            }
            error = nil
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Formatting

func fmtSize(_ bytes: Double) -> String {
    let gb = bytes / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = bytes / 1_048_576
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    return String(format: "%.0f KB", bytes / 1024)
}

func fmtCount(_ n: Double) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
    if n >= 1_000 { return String(format: "%.2fK", n / 1_000) }
    return String(format: "%.0f", n)
}

func fmtToken(_ n: Double) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fK", n / 1_000) }
    return String(format: "%.0f", n)
}

struct ErrorBanner: View {
    @Environment(\.palette) private var p
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.system(size: 13)).foregroundStyle(p.text).lineLimit(3)
            Spacer()
            Button("重试", action: retry).font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
        }
        .padding(14)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}