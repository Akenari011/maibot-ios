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
                ManagementItem(icon: "wifi.router", title: "适配器设置", route: .other("适配器设置")),
                ManagementItem(icon: "cpu", title: "机器人管理", route: .bots),
            ]),
            ManagementGroup(title: "资源管理", items: [
                ManagementItem(icon: "book", title: "学习", route: .other("学习")),
                ManagementItem(icon: "externaldrive", title: "长期记忆", route: .memory),
            ]),
            ManagementGroup(title: "扩展集成", items: [
                ManagementItem(icon: "puzzlepiece.extension", title: "插件配置", route: .plugins),
                ManagementItem(icon: "square.grid.2x2", title: "插件市场", route: .other("插件市场")),
            ]),
            ManagementGroup(title: "高级工具", items: [
                ManagementItem(icon: "text.alignleft", title: "提示词管理", route: .prompts),
                ManagementItem(icon: "arrow.left.arrow.right", title: "数据传输", route: .files),
            ]),
            ManagementGroup(title: "运行日志", items: [
                ManagementItem(icon: "doc.text", title: "日志", route: .logs),
                ManagementItem(icon: "brain", title: "推理过程", route: .other("推理过程")),
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
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer").font(.system(size: 34, weight: .light)).foregroundStyle(p.textTertiary)
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(p.text)
            Text("该页面正在按网页版重构中").font(.system(size: 13)).foregroundStyle(p.textSecondary)
            Text("部分子页在网页版依赖额外登录态或运行参数（如插件市场、推理过程、适配器设置），iOS 暂以占位保留，可先用网页版操作。")
                .font(.system(size: 11)).foregroundStyle(p.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
