//
//  SettingsView.swift
//  MaiBot
//

import SwiftUI

struct SettingsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @AppStorage("maibot.theme") private var themeRaw = ThemePreference.system.rawValue
    @State private var editingHost = false
    @State private var hostDraft = ""
    @State private var confirmSignOut = false

    private var preference: Binding<ThemePreference> {
        Binding(
            get: { ThemePreference(rawValue: themeRaw) ?? .system },
            set: { themeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    appearance
                    server
                    account
                    about
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(p.background)
            .navigationTitle("设置")
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .alert("修改服务器地址", isPresented: $editingHost) {
            TextField("https://maibot.example.com", text: $hostDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let u = URL(string: hostDraft.trimmingCharacters(in: .whitespaces)),
                   u.scheme != nil, u.host != nil {
                    client.baseURL = u
                    Task { await auth.signOut(client: client) }
                }
            }
        }
        .confirmationDialog("退出登录后会清除保存的会话", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await auth.signOut(client: client) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var appearance: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("外观").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textMute)

                ForEach(ThemePreference.allCases) { pref in
                    Button {
                        preference.wrappedValue = pref
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pref.symbol)
                                .font(.system(size: 14))
                                .frame(width: 22)
                                .foregroundStyle(preference.wrappedValue == pref ? p.accent : p.textDim)
                            Text(pref.title)
                                .font(.system(size: 14))
                                .foregroundStyle(p.text)
                            Spacer()
                            if preference.wrappedValue == pref {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(p.accent)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var server: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textMute)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.baseURL.host() ?? "—")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(p.text)
                        Text(client.baseURL.absoluteString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.textMute)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("修改") {
                        hostDraft = client.baseURL.absoluteString
                        editingHost = true
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var account: some View {
        Panel {
            Button(role: .destructive) {
                confirmSignOut = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("退出登录")
                    Spacer()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(p.danger)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var about: some View {
        Panel(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MaiBot 面板").font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                    Text("非官方客户端 · SwiftUI")
                        .font(.system(size: 11)).foregroundStyle(p.textMute)
                }
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(p.textDim)
            }
        }
    }
}
