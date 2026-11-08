//
//  SettingsView.swift
//  MaiBot
//

import SwiftUI

struct SettingsView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var editingHost = false
    @State private var hostDraft = ""
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("服务器").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.textSecondary)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(client.baseURL.host() ?? "—").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                                Text(client.baseURL.absoluteString).font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(p.textSecondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("修改") { hostDraft = client.baseURL.absoluteString; editingHost = true }
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(p.orange)
                        }
                    }
                }

                Panel {
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("退出登录").font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                Panel(padding: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MaiBot 面板").font(.system(size: 14, weight: .medium)).foregroundStyle(p.text)
                            Text("非官方客户端 · SwiftUI").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                        }
                        Spacer()
                        Text("1.0").font(.system(size: 13, design: .monospaced)).foregroundStyle(p.textSecondary)
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .background(p.bg)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .alert("修改服务器地址", isPresented: $editingHost) {
            TextField("https://maibot.example.com", text: $hostDraft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let u = URL(string: hostDraft.trimmingCharacters(in: .whitespaces)), u.scheme != nil, u.host != nil {
                    client.baseURL = u
                    Task { await auth.signOut(client: client) }
                }
            }
        }
        .confirmationDialog("退出登录会清除保存的会话", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await auth.signOut(client: client) } }
            Button("取消", role: .cancel) {}
        }
    }
}