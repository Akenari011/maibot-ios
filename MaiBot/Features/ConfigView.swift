//
//  ConfigView.swift
//  MaiBot
//
//  Read-only view of the host's WebUI settings. Editing stays in the browser —
//  these fields change listening ports and cookie flags, which is not something
//  to do from a phone by accident.
//

import SwiftUI

struct ConfigView: View {
    @Environment(APIClient.self) private var client
    @Environment(AuthStore.self) private var auth
    @Environment(\.palette) private var p

    @State private var settings: HostSettings?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    }

                    if let web = settings?.webui {
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionTitle("WebUI")
                                row("监听端口", web.port.map(String.init) ?? "—")
                                row("对外启用", web.enabled == true ? "是" : "否")
                                row("反爬模式", web.antiCrawlerMode ?? "—")
                                row("公网地址", web.publicBaseURL?.isEmpty == false ? web.publicBaseURL! : "未设置")
                                if let hosts = web.hosts, !hosts.isEmpty {
                                    row("绑定地址", hosts.joined(separator: ", "))
                                }
                            }
                        }
                    }

                    if let rev = settings?.revision {
                        Panel(padding: 12) {
                            HStack {
                                Text("配置版本").font(.system(size: 11)).foregroundStyle(p.textMute)
                                Spacer()
                                Text(String(rev.prefix(12)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(p.textDim)
                            }
                        }
                    }

                    Panel(padding: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(p.info)
                            Text("修改配置请前往网页版，避免误改监听端口导致面板失联。")
                                .font(.system(size: 12))
                                .foregroundStyle(p.textDim)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(p.background)
            .navigationTitle("配置")
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await load() }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(p.textMute)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundStyle(p.textDim)
            Spacer()
            Text(v).font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func load() async {
        do {
            settings = try await client.settings()
            error = nil
        } catch APIError.unauthorized {
            await auth.signOut(client: client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
