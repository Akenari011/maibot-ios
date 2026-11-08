//
//  SettingsView.swift
//  MaiBot
//
//  Settings page with six tabs (通用/机器人/外观/安全/其他/关于), matching the
//  web dashboard's settings structure. modern light styling.
//

import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case general = "通用", bot = "机器人", appearance = "外观", security = "安全", other = "其他", about = "关于"
}

struct SettingsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var tab: SettingsTab = .general
    @State private var botName = "—"
    @State private var botStatus = "—"

    @State private var editingHost = false
    @State private var hostDraft = ""
    @State private var confirmSignOut = false

    @State private var newToken = ""
    @State private var generatedToken: String?
    @State private var busy = false
    @State private var notice: String?
    @State private var confirmReset = false
    @AppStorage("theme.mode") private var themeMode = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置").font(.system(size: 34, weight: .bold)).tracking(-0.4).foregroundStyle(p.text)
                tabBar
                if let notice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Group {
                    switch tab {
                    case .general: generalTab
                    case .bot: botTab
                    case .appearance: appearanceTab
                    case .security: securityTab
                    case .other: otherTab
                    case .about: aboutTab
                    }
                }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(p.bg)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBot() }
        .alert("修改服务器地址", isPresented: $editingHost) {
            TextField("https://maibot.example.com", text: $hostDraft)
                .textInputAutocapitalization(.never).keyboardType(.URL)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let u = URL(string: hostDraft.trimmingCharacters(in: .whitespaces)), u.scheme != nil, u.host != nil {
                    client.baseURL = u; Task { await auth.signOut(client: client) }
                }
            }
        }
        .confirmationDialog("退出登录会清除保存的会话", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await auth.signOut(client: client) } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("重置设置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置", role: .destructive) { Task { await doReset() } }
            Button("取消", role: .cancel) {}
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Button { withAnimation(.easeOut(duration: Motion.fast)) { tab = t } } label: {
                        Text(t.rawValue)
                            .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? .white : p.text)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(tab == t ? p.orange : p.card, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: tabs

    private var generalTab: some View {
        card {
            row("服务器") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.baseURL.host() ?? "—").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                    Text(client.baseURL.absoluteString).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.textSecondary).lineLimit(1)
                }
                Spacer()
                Button("修改") { hostDraft = client.baseURL.absoluteString; editingHost = true }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange)
            }
            divider
            row("语言") { Text("简体中文").font(.system(size: 14)).foregroundStyle(p.text); Spacer() }
            divider
            row("当前版本") { Text("1.0").font(.system(size: 14, design: .monospaced)).foregroundStyle(p.textSecondary); Spacer() }
        }
    }

    private var botTab: some View {
        card {
            row("当前 Bot") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(botName).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                    Text(botStatus).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var appearanceTab: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("主题").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary)
                Picker("主题", selection: $themeMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }.pickerStyle(.segmented)
                Text("强调色").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary).padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach([0xE06F06, 0x2EB37C, 0xEB8A2E, 0xA24FD9, 0xE04F8A], id: \.self) { hex in
                        Circle().fill(Color(hex: UInt32(hex))).frame(width: 26, height: 26)
                            .overlay { Circle().strokeBorder(hex == 0xE06F06 ? p.text : .clear, lineWidth: 2) }
                    }
                }
            }
        }
    }

    private var securityTab: some View {
        VStack(spacing: 14) {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WebUI 访问 Token").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary)
                    SecureField("输入新 Token（≥10位，含大小写与符号）", text: $newToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14)).padding(10)
                        .background(p.iconCircle, in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 10) {
                        Button(busy ? "处理中…" : "更新 Token") { Task { await doUpdateToken() } }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(p.orange, in: Capsule())
                            .disabled(busy || newToken.count < 10)
                        Button("重新生成") { Task { await doRegenerate() } }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(p.iconCircle, in: Capsule())
                    }
                    if let t = generatedToken {
                        Text("新 Token（仅显示一次）：").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                        Text(t).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.text).textSelection(.enabled)
                    }
                }
            }
            card {
                Button(role: .destructive) { confirmSignOut = true } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("退出登录").font(.system(size: 15, weight: .medium))
                        Spacer()
                    }.foregroundStyle(.red).contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
    }

    private var otherTab: some View {
        VStack(spacing: 14) {
            card {
                row("清除日志缓存") { Spacer(); Button("清除") { notice = "已请求清除（客户端缓存）" }.font(.system(size: 13, weight: .medium)).foregroundStyle(p.orange) }
                divider
                row("重置设置") { Spacer(); Button("重置") { confirmReset = true }.font(.system(size: 13, weight: .medium)).foregroundStyle(.red) }
            }
        }
    }

    private var aboutTab: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("MaiBot 面板 · iOS").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                Text("非官方客户端 · SwiftUI · 1.0").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                Text("与网页版 dashboard 对齐重构中").font(.system(size: 12)).foregroundStyle(p.textTertiary)
            }
        }
    }

    // MARK: helpers

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) { Text(title).font(.system(size: 14)).foregroundStyle(p.text); content() }
    }
    private var divider: some View { Rectangle().fill(p.separator).frame(height: 1) }
    private func themeChip(_ t: String, on: Bool) -> some View {
        Text(t).font(.system(size: 12, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? .white : p.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? p.orange : p.iconCircle, in: Capsule())
    }

    private func loadBot() async {
        if let mode = try? await client.hostMode(), let id = mode.selectedBotID {
            if let list = try? await client.bots(), let b = list.first(where: { $0.botID == id }) {
                botName = b.name; botStatus = b.statusLabel
            } else { botName = id }
        }
    }
    private func doUpdateToken() async {
        busy = true; defer { busy = false }
        do { try await client.updateToken(newToken); notice = "Token 已更新，请重新登录"; newToken = "" }
        catch { notice = "更新失败：\(error.localizedDescription)" }
    }
    private func doRegenerate() async {
        busy = true; defer { busy = false }
        do { generatedToken = try await client.regenerateToken(); notice = "已重新生成 Token" }
        catch { notice = "生成失败：\(error.localizedDescription)" }
    }
    private func doReset() async {
        do { try await client.resetSetup(resetPassword: false); notice = "已重置设置" }
        catch { notice = "重置失败：\(error.localizedDescription)" }
    }
}
