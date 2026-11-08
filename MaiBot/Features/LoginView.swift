//
//  LoginView.swift
//  MaiBot
//
//  The panel issues an HttpOnly cookie, so signing in means running the real
//  browser flow. This uses SwiftUI's native WebView (iOS 26+) instead of
//  wrapping WKWebView by hand — navigation state, progress and gestures are
//  all first-class SwiftUI values now.
//

import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p

    @State private var page = WebPage()
    @State private var editingHost = false
    @State private var hostDraft = ""

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                WebView(page)
                    .webViewBackForwardNavigationGestures(.enabled)
                    .webViewMagnificationGestures(.enabled)
                    .webViewTextSelection(.enabled)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) {
                        if page.isLoading {
                            ProgressView(value: page.estimatedProgress)
                                .progressViewStyle(.linear)
                                .tint(p.accent)
                        }
                    }

                footer
            }
        }
        .task {
            if page.url == nil {
                page.load(URLRequest(url: client.baseURL))
            }
        }
        // Every landing is a chance for the panel cookie to exist.
        .onChange(of: page.url) { _, _ in
            Task { await auth.capture(store: .default(), client: client) }
        }
        .onChange(of: page.isLoading) { _, isLoading in
            if !isLoading {
                Task { await auth.capture(store: .default(), client: client) }
            }
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
                    page.load(URLRequest(url: u))
                }
            }
        } message: {
            Text("填写面板的完整地址，例如 https://maibot.galmaster.online")
        }
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            p.background
            // A slow mesh drift behind the glass header/footer.
            MeshGradient(
                width: 3, height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1)
                ],
                colors: [
                    p.accent.opacity(0.22), p.background, p.info.opacity(0.14),
                    p.background, p.background, p.background,
                    p.violet.opacity(0.12), p.background, p.accent.opacity(0.10)
                ]
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(p.accent.opacity(0.18))
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(p.accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MaiBot 面板")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(p.text)
                    Text(client.baseURL.host() ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(p.textDim)
                }

                Spacer()

                Button {
                    hostDraft = client.baseURL.absoluteString
                    editingHost = true
                } label: {
                    Image(systemName: "server.rack")
                        .font(.system(size: 15))
                        .foregroundStyle(p.textDim)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
            Text("登录在系统网页视图中完成，凭据不经过本应用")
                .font(.system(size: 11))
        }
        .foregroundStyle(p.textMute)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}
