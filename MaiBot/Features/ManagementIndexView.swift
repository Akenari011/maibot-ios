//
//  ManagementIndexView.swift
//  MaiBot
//
//  管理 tab = 设置菜单索引（网页版 routes/manage.tsx 的手机布局）。
//  大标题「管理」+ 搜索「搜索页面或设置项」+ 分组卡（圆角 24、细边、行高 54、
//  图标 22 线形 + 标签 + chevron）。机器人管理是其中一个子页。
//

import SwiftUI

struct ManagementItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let route: ManageRoute
}

struct ManagementGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [ManagementItem]
}

struct ManagementIndexView: View {
    @Environment(\.palette) private var p
    @State private var search = ""

    private var groups: [ManagementGroup] {
        [
            ManagementGroup(title: "配置管理", items: [
                ManagementItem(icon: "slider.horizontal.3", title: "麦麦设置", route: .config),
                ManagementItem(icon: "cube", title: "模型管理", route: .models),
                ManagementItem(icon: "wifi.router", title: "适配器设置", route: .adapter),
                ManagementItem(icon: "cpu", title: "机器人管理", route: .bots),
            ]),
            ManagementGroup(title: "资源管理", items: [
                ManagementItem(icon: "book", title: "学习", route: .learning),
                ManagementItem(icon: "face.smiling", title: "表情", route: .emoji),
                ManagementItem(icon: "text.bubble", title: "表达方式", route: .expression),
                ManagementItem(icon: "character.bubble", title: "黑话", route: .jargon),
                ManagementItem(icon: "person.crop.circle", title: "人物", route: .person),
                ManagementItem(icon: "externaldrive", title: "长期记忆", route: .memory),
                ManagementItem(icon: "point.3.connected.trianglepath.dotted", title: "知识图谱", route: .graph),
            ]),
            ManagementGroup(title: "扩展集成", items: [
                ManagementItem(icon: "cpu", title: "Agent 设置", route: .agent),
                ManagementItem(icon: "desktopcomputer", title: "电脑使用", route: .computer),
                ManagementItem(icon: "server.rack", title: "MCP 设置", route: .mcp),
                ManagementItem(icon: "puzzlepiece.extension", title: "插件配置", route: .plugins),
                ManagementItem(icon: "square.grid.2x2", title: "插件市场", route: .market),
            ]),
            ManagementGroup(title: "高级工具", items: [
                ManagementItem(icon: "text.alignleft", title: "提示词管理", route: .prompts),
                ManagementItem(icon: "bubble.left.and.text.bubble.right", title: "聊天管理", route: .chatManagement),
                ManagementItem(icon: "arrow.left.arrow.right", title: "数据传输", route: .files),
            ]),
            ManagementGroup(title: "运行日志", items: [
                ManagementItem(icon: "doc.text", title: "日志", route: .logs),
                ManagementItem(icon: "brain", title: "推理过程", route: .reasoning),
                ManagementItem(icon: "chart.bar", title: "统计", route: .statistics),
            ]),
            ManagementGroup(title: "系统", items: [
                ManagementItem(icon: "gearshape", title: "设置", route: .settings),
            ]),
        ]
    }

    private var filteredGroups: [ManagementGroup] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            let items = g.items.filter { $0.title.lowercased().contains(q) }
            return items.isEmpty ? nil : ManagementGroup(title: g.title, items: items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("管理").font(.system(size: 34, weight: .bold)).foregroundStyle(p.text)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(p.textSecondary)
                    TextField("搜索页面或设置项", text: $search)
                        .font(.system(size: 15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(p.iconCircle, in: RoundedRectangle(cornerRadius: 12))

                if filteredGroups.isEmpty {
                    Text("没有匹配的页面").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }

                ForEach(filteredGroups) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(g.title).font(.system(size: 13)).foregroundStyle(p.textSecondary).padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, item in
                                NavigationLink(value: item.route) {
                                    HStack(spacing: 14) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 18, weight: .regular))
                                            .frame(width: 24)
                                            .foregroundStyle(p.text)
                                        Text(item.title).font(.system(size: 16)).foregroundStyle(p.text)
                                        if case .other = item.route {
                                            Text("即将").font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(p.textTertiary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(p.iconCircle, in: Capsule())
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(p.textTertiary)
                                    }
                                    .padding(.horizontal, 16).frame(height: 54)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(PressableStyle())
                                if idx < g.items.count - 1 {
                                    Rectangle().fill(p.separator).frame(height: 1).padding(.leading, 54)
                                }
                            }
                        }
                        .background(p.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(p.separator, lineWidth: 1) }
                    }
                }

                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(p.bg)
        .navigationBarHidden(true)
    }
}

struct PlaceholderPage: View {
    @Environment(\.palette) private var p
    @Environment(APIClient.self) private var client
    let title: String

    private var webURL: URL? {
        let map = ["插件市场": "/plugin-mirrors", "推理过程": "/reasoning-process",
                   "适配器设置": "/adapter-management", "学习": "/resource/learning",
                   "长期记忆": "/resource/knowledge-base"]
        guard let path = map[title] else { return nil }
        var comp = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)
        comp?.path = path
        return comp?.url
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer").font(.system(size: 34, weight: .light)).foregroundStyle(p.textTertiary)
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(p.text)
            Text("该页面正在按网页版重构中").font(.system(size: 13)).foregroundStyle(p.textSecondary)
            Text("部分子页在网页版依赖额外登录态或运行参数（如插件市场、推理过程、适配器设置），iOS 暂以占位保留，可先用网页版操作。")
                .font(.system(size: 11)).foregroundStyle(p.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 30)
            if let url = webURL {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("在网页版打开").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(p.orange, in: Capsule())
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
