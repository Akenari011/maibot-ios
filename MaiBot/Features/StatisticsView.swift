//
//  StatisticsView.swift
//  MaiBot
//
//  统计页：复用 dashboard 接口，展示概览 / 请求趋势 / Token / 模型分布。
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var data: Dashboard?
    @State private var range = 24
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("统计").font(.system(size: 34, weight: .bold)).tracking(-0.4).foregroundStyle(p.text)
                    Spacer()
                    SegmentedChips(items: [24, 168, 720], label: { $0 == 24 ? "24小时" : ($0 == 168 ? "7天" : "30天") }, selection: $range)
                }
                if let e = error { ErrorBanner(message: e) { Task { await load() } } }
                if let d = data {
                    summaryCard(d.summary)
                    trendCard(d)
                    tokenCard(d)
                    modelCard(d)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(p.bg)
        .pageChrome("统计", showsTitle: false)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    private func summaryCard(_ s: Dashboard.Summary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 24) {
                    stat("总请求数", fmtCount(s.totalRequests), 26)
                    stat("总花费", "¥" + String(format: "%.2f", s.totalCost), 26)
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                    stat("Token消耗", fmtToken(s.totalTokens), 18)
                    stat("平均响应", String(format: "%.2fs", s.avgResponseTime), 18)
                    stat("在线时长", String(format: "%.1fh", s.onlineTime / 3600), 18)
                    stat("消息", fmtCount(s.totalMessages), 18)
                }
            }
        }
    }

    private func stat(_ t: String, _ v: String, _ size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(.system(size: 12)).foregroundStyle(p.textSecondary)
            Text(v).font(.system(size: size, weight: .semibold)).tracking(-0.3).foregroundStyle(p.text)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendCard(_ d: Dashboard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("请求趋势", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                if d.hourlyData.isEmpty {
                    Text("暂无数据").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Chart(d.hourlyData) { pt in
                    LineMark(x: .value("时间", pt.hourLabel), y: .value("请求", pt.requests))
                        .foregroundStyle(p.orange).interpolationMethod(.catmullRom)
                    AreaMark(x: .value("时间", pt.hourLabel), y: .value("请求", pt.requests))
                        .foregroundStyle(p.orange.opacity(0.08)).interpolationMethod(.catmullRom)
                }
                .frame(height: 170)
            }
        }
    }

    private func tokenCard(_ d: Dashboard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Token 消耗", systemImage: "chart.bar.doc.horizontal").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                if d.hourlyData.isEmpty {
                    Text("暂无数据").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Chart(d.hourlyData) { pt in
                    BarMark(x: .value("时间", pt.hourLabel), y: .value("Token", pt.inputTokens)).foregroundStyle(p.orange)
                }
                .frame(height: 160)
            }
        }
    }

    private func modelCard(_ d: Dashboard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("模型分布", systemImage: "cpu").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                if d.modelStats.isEmpty {
                    Text("暂无数据").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                } else {
                    let maxReq = max(1, d.modelStats.map { $0.requestCount }.max() ?? 1)
                    ForEach(d.modelStats) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(m.modelName).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text).lineLimit(1)
                                Spacer()
                                Text(fmtCount(m.requestCount) + " 次").font(.system(size: 12, design: .monospaced)).foregroundStyle(p.textSecondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(p.iconCircle)
                                    Capsule().fill(p.orange).frame(width: max(4, geo.size.width * CGFloat(m.requestCount / maxReq)))
                                }
                            }.frame(height: 7)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let mode = try await client.hostMode()
            guard let id = mode.selectedBotID else { return }
            data = try await client.dashboard(botID: id, hours: range)
            error = nil
        } catch APIError.unauthorized { await auth.signOut(client: client) }
        catch { self.error = error.localizedDescription }
    }
}
