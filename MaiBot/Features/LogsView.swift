//
//  LogsView.swift
//  MaiBot
//
//  Log page reconstructed from the web dashboard's LogTerminalPane
//  (dashboard/src/routes/logs.tsx). The terminal keeps the web page's fixed
//  dark-brown palette regardless of theme:
//    card #633312, scroll area #211607, timestamp gray, module cyan,
//    level colours INFO=blue WARNING=amber ERROR=red CRITICAL=dark-red bold.
//  Data comes from LogsClient (unified ws: subscribe logs/main).
//

import SwiftUI
import UIKit

private enum LogLevels {
    static let order: [String: Int] = [
        "DEBUG": 10, "INFO": 20, "WARNING": 30, "ERROR": 40, "CRITICAL": 50,
    ]
    static func rank(_ level: String) -> Int { order[level.uppercased()] ?? 0 }
    static func short(_ level: String) -> String { String(level.prefix(4)).uppercased() }
    static func color(_ level: String) -> Color {
        switch level.uppercased() {
        case "DEBUG":    return Color(hex: 0x9CA3AF)
        case "INFO":     return Color(hex: 0x3B82F6)
        case "WARNING":  return Color(hex: 0xCA8A04)
        case "ERROR":    return Color(hex: 0xDC2626)
        case "CRITICAL": return Color(hex: 0xB91C1C)
        default:         return Color(hex: 0xD1D5DB)
        }
    }
}

private enum LogFontSize: String, CaseIterable {
    case xs, sm, base
    var label: String { self == .xs ? "小" : (self == .sm ? "中" : "大") }
    var point: CGFloat { self == .xs ? 10 : (self == .sm ? 12 : 14) }
}

private enum LevelFilter: String, CaseIterable {
    case all, DEBUG, INFO, WARNING, ERROR, CRITICAL
    var label: String {
        switch self {
        case .all: return "全部级别"
        case .DEBUG: return "DEBUG 及以上"
        case .INFO: return "INFO 及以上"
        case .WARNING: return "WARNING 及以上"
        case .ERROR: return "ERROR 及以上"
        case .CRITICAL: return "CRITICAL"
        }
    }
}

private struct ModuleOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct LogsView: View {
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logs: LogsClient?
    @State private var search = ""
    @State private var filterOpen = false
    @State private var sourcesOpen = false
    @State private var exportURL: URL?
    @State private var hiddenModules: Set<String> = []
    @State private var dateFrom: Date?
    @State private var dateTo: Date?

    @AppStorage("log.level") private var levelFilterRaw = "INFO"
    @AppStorage("log.font") private var fontRaw = "xs"
    @AppStorage("log.lineSpacing") private var lineSpacing = 4.0
    @AppStorage("log.autoFollow") private var autoFollow = true
    @AppStorage("log.hiddenModules") private var hiddenRaw = ""

    private var levelFilter: LevelFilter { LevelFilter(rawValue: levelFilterRaw) ?? .INFO }
    private var fontSize: LogFontSize { LogFontSize(rawValue: fontRaw) ?? .xs }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let logs {
                statusLine(logs)
                terminal(logs)
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $filterOpen) { filterSheet }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let url = exportURL { LogsShareSheet(items: [url]) }
        }
        .onAppear { hiddenModules = Set(hiddenRaw.split(separator: ",").map(String.init)) }
        .task {
            if logs == nil {
                let c = LogsClient(client: client)
                logs = c
                await c.connect()
            }
        }
    }

    private var allEntries: [LogEntry] { logs?.entries ?? [] }

    private var modules: [ModuleOption] {
        var seen = [String: String]()
        for e in allEntries {
            let id = e.module.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty, seen[id] == nil { seen[id] = displayModule(e) }
        }
        return seen.map { ModuleOption(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var filtered: [LogEntry] {
        let q = search.lowercased()
        let minRank = levelFilter == .all ? Int.min : LogLevels.rank(levelFilter.rawValue)
        return allEntries.filter { e in
            if hiddenModules.contains(e.module) { return false }
            if let d = parseTime(e.timestamp) {
                if let df = dateFrom, d < Calendar.current.startOfDay(for: df) { return false }
                if let dt = dateTo, d > (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dt)) ?? dt) { return false }
            }
            if minRank != Int.min, LogLevels.rank(e.level) < minRank { return false }
            if !q.isEmpty {
                let hit = e.message.lowercased().contains(q)
                    || e.module.lowercased().contains(q)
                    || displayModule(e).lowercased().contains(q)
                if !hit { return false }
            }
            return true
        }
    }

    private func displayModule(_ e: LogEntry) -> String {
        if let n = e.moduleDisplayName?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != e.module { return n }
        return e.module
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(p.textTertiary)
                TextField("搜索日志...", text: $search)
                    .font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(p.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(p.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }

            HStack(spacing: 8) {
                Button { sourcesOpen.toggle() } label: {
                    pillLabel("来源", trailing: "全部 \(modules.count)")
                }.buttonStyle(.plain)
                .popover(isPresented: $sourcesOpen) { sourcesPanel }

                Button { filterOpen = true } label: {
                    HStack(spacing: 6) {
                        pillLabel("筛选", trailing: levelFilter == .all ? "全部级别" : "\(LogLevels.short(levelFilter.rawValue))＋")
                        if levelFilter != .all || dateFrom != nil || dateTo != nil {
                            Circle().fill(p.orange).frame(width: 6, height: 6)
                        }
                    }
                }.buttonStyle(.plain)

                Spacer()

                Button { autoFollow.toggle() } label: {
                    pillLabel(autoFollow ? "暂停跟随" : "跟随最新", icon: autoFollow ? "pause.fill" : "play.fill")
                }.buttonStyle(.plain)

                iconButton("square.and.arrow.up") { exportURL = makeExportFile() }
                    .disabled(filtered.isEmpty)
                iconButton("trash") { logs?.clear() }
                    .disabled(allEntries.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pillLabel(_ title: String, trailing: String? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 12, weight: .medium))
            if let trailing { Text(trailing).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textSecondary) }
        }
        .foregroundStyle(p.text)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(p.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13))
                .foregroundStyle(p.text)
                .frame(width: 32, height: 32)
                .background(p.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.separator) }
        }.buttonStyle(.plain)
    }

    private func statusLine(_ logs: LogsClient) -> some View {
        HStack(spacing: 6) {
            Circle().fill(logs.status == .ready ? p.green : .red).frame(width: 7, height: 7)
            Text(logs.status == .ready ? "已连接" : "未连接").font(.system(size: 11)).foregroundStyle(p.text)
            Text("\(filtered.count) / \(allEntries.count) 条")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textSecondary)
            if !logs.debug.isEmpty {
                Text(logs.debug).font(.system(size: 9)).foregroundStyle(p.textTertiary)
            }
            Spacer()
            if case .failed = logs.status {
                Button("重连") { Task { await logs.connect() } }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(p.orange)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private func terminal(_ logs: LogsClient) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text("暂无日志数据")
                            .font(.system(size: fontSize.point, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x6B7280))
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else {
                        ForEach(filtered) { e in row(e).id(e.id) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .background(Color(hex: 0x211607))
            .onChange(of: filtered.count) { _, _ in
                guard autoFollow else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(Color(hex: 0x633312))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x24170F), lineWidth: 1) }
        .padding(.horizontal, 12)
        .padding(.bottom, 84)
    }

    private func row(_ e: LogEntry) -> some View {
        let moduleColor = Color(hexString: e.moduleColor) ?? Color(hex: 0x22D3EE)
        let moduleBold = e.moduleBold ?? false
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(shortTimestamp(e.timestamp))
                    .font(.system(size: fontSize.point, design: .monospaced)).foregroundStyle(Color(hex: 0x9CA3AF))
                Text("[\(LogLevels.short(e.level))]")
                    .font(.system(size: fontSize.point, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LogLevels.color(e.level))
            }
            Text(displayModule(e))
                .font(.system(size: fontSize.point, weight: moduleBold ? .bold : .regular, design: .monospaced))
                .foregroundStyle(moduleColor).lineLimit(1)
            Text(e.message)
                .font(.system(size: fontSize.point, design: .monospaced))
                .foregroundStyle(Color(hex: 0xD1D5DB))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, lineSpacing / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseTime(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        guard let d = f.date(from: t) else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        var comps = Calendar.current.dateComponents([.month, .day, .hour, .minute, .second], from: d)
        comps.year = year
        return Calendar.current.date(from: comps)
    }

    private func shortTimestamp(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 19 {
            let i = t.index(t.startIndex, offsetBy: 5)
            var rest = String(t[i...])
            if rest.hasPrefix("T") { rest = " " + rest.dropFirst() }
            return rest
        }
        return s
    }

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("来源（\(modules.count - hiddenModules.count)/\(modules.count)）").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("全选") { hiddenModules.removeAll(); hiddenRaw = "" }.font(.system(size: 11)).foregroundStyle(p.orange)
                Button("全不选") { hiddenModules = Set(modules.map { $0.id }); hiddenRaw = modules.map { $0.id }.joined(separator: ",") }.font(.system(size: 11)).foregroundStyle(p.orange)
            }
            if modules.isEmpty {
                Text("暂无来源").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(modules) { m in
                            Button { toggle(m.id) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: hiddenModules.contains(m.id) ? "square" : "checkmark.square.fill")
                                        .font(.system(size: 12)).foregroundStyle(hiddenModules.contains(m.id) ? p.textTertiary : p.orange)
                                    Text(m.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.text).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 3)
                                .contentShape(.rect)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private func toggle(_ id: String) {
        if hiddenModules.contains(id) { hiddenModules.remove(id) } else { hiddenModules.insert(id) }
        hiddenRaw = hiddenModules.joined(separator: ",")
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("级别") {
                    Picker("最低级别", selection: $levelFilterRaw) {
                        ForEach(LevelFilter.allCases, id: \.rawValue) { f in Text(f.label).tag(f.rawValue) }
                    }
                }
                Section("显示") {
                    Picker("字号", selection: $fontRaw) {
                        ForEach(LogFontSize.allCases, id: \.rawValue) { s in Text(s.label).tag(s.rawValue) }
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading) {
                        HStack { Text("行距"); Spacer(); Text("\(Int(lineSpacing))px").foregroundStyle(.secondary) }
                        Slider(value: $lineSpacing, in: 0...12, step: 2)
                    }
                    Toggle("自动跟随最新", isOn: $autoFollow)
                }
                Section("时间范围") {
                    HStack {
                        Text("起始")
                        Spacer()
                        DatePicker("", selection: Binding(get: { dateFrom ?? Date() }, set: { dateFrom = $0 }), displayedComponents: .date)
                            .labelsHidden()
                        if dateFrom != nil { Button("清除") { dateFrom = nil }.font(.system(size: 12)).foregroundStyle(.red) }
                    }
                    HStack {
                        Text("结束")
                        Spacer()
                        DatePicker("", selection: Binding(get: { dateTo ?? Date() }, set: { dateTo = $0 }), displayedComponents: .date)
                            .labelsHidden()
                        if dateTo != nil { Button("清除") { dateTo = nil }.font(.system(size: 12)).foregroundStyle(.red) }
                    }
                }
                Section {
                    Button("重置筛选", role: .destructive) { search = ""; levelFilterRaw = "INFO"; dateFrom = nil; dateTo = nil }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { filterOpen = false } } }
        }
    }

    private func makeExportFile() -> URL? {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "logs-\(df.string(from: Date())).txt"
        let text = filtered.map { e in
            let lvl = e.level.padding(toLength: max(8, e.level.count), withPad: " ", startingAt: 0)
            return "\(e.timestamp) [\(lvl)] [\(e.module)] \(e.message)"
        }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try text.data(using: .utf8)?.write(to: url); return url } catch { return nil }
    }
}

private struct LogsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension Color {
    /// Parse "#RRGGBB" / "RRGGBB" / "#RRGGBBAA" from the panel's moduleColor.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 8 {
            self = Color(hex: v >> 8, alpha: Double(v & 0xFF) / 255)
        } else {
            self = Color(hex: v)
        }
    }
}
