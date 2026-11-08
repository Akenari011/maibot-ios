//
//  LogsView.swift
//  MaiBot
//
//  Real-time log viewer backed by the panel's unified websocket
//  (subscribe logs/main -> snapshot + entry). Monospaced, tailing, with a
//  severity filter.
//

import SwiftUI

struct LogsView: View {
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p

    @State private var logs: LogsClient?
    @State private var filter = "全部"

    private let filters = ["全部", "错误", "警告"]

    private var filtered: [LogEntry] {
        guard let logs else { return [] }
        switch filter {
        case "错误": return logs.entries.filter { $0.level == "ERROR" || $0.level == "CRITICAL" }
        case "警告": return logs.entries.filter { $0.level == "WARNING" }
        default:     return logs.entries
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let logs {
                content(logs)
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if logs == nil {
                let c = LogsClient(client: client)
                logs = c
                await c.connect()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let logs {
                switch logs.status {
                case .ready:     statusDot("实时", p.green)
                case .connecting: statusDot("连接中…", p.orange)
                case .idle:      statusDot("未连接", p.textTertiary)
                case .failed(_): statusDot("连接失败", .red)
                }
                Text("\(logs.entries.count) 条")
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            SegmentedChips(items: filters, label: { $0 }, selection: $filter)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func statusDot(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(c)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(c.opacity(0.12), in: .capsule)
    }

    @ViewBuilder
    private func content(_ logs: LogsClient) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 36, weight: .light)).foregroundStyle(p.textTertiary)
                            Text(logs.status == .ready ? "暂无日志" : "正在连接日志流…")
                                .font(.system(size: 14)).foregroundStyle(p.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 70)
                    }
                    ForEach(filtered) { e in
                        row(e)
                        Divider().overlay(p.separator.opacity(0.6))
                    }
                    Color.clear.frame(height: 1).id("log-end")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 90)
            }
            .onChange(of: filtered.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("log-end", anchor: .bottom) }
            }
        }
    }

    private func row(_ e: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(e.clock)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(p.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text(e.level)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(levelColor(e.level))
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if !e.module.isEmpty {
                    Text(e.module)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(p.textSecondary)
                        .lineLimit(1)
                }
                Text(e.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(p.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "ERROR", "CRITICAL": return .red
        case "WARNING":           return p.orange
        case "DEBUG":             return p.textTertiary
        default:                  return p.green
        }
    }
}
