//
//  LoginView.swift
//  MaiBot
//
//  Sign-in runs inside a WKWebView, but not a stock one. Two things have to
//  be configured or the login page is only half usable:
//
//  1. limitsNavigationsToAppBoundDomains = true, together with the
//     WKAppBoundDomains list in Info.plist. Without this, WebAuthn is simply
//     unavailable in WKWebView and tapping the hardware-key row does nothing.
//
//  2. A Safari-shaped custom user agent. GitHub refuses OAuth inside a
//     default WKWebView UA (it detects the missing "Safari/..." token), and
//     the GitHub row in the sign-in list therefore cannot complete.
//
//  Both are app-side only; the gateway needs no changes.
//

import SwiftUI
import WebKit

/// Safari on the same OS version. Only the trailing token matters to GitHub.
let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(APIClient.self) private var client
    @Environment(\.palette) private var p

    @State private var progress: Double = 0
    @State private var loading = true
    @State private var editingHost = false
    @State private var hostDraft = ""
    @State private var reloadToken = UUID()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                MaiLoginWebView(
                    url: client.baseURL,
                    reloadToken: reloadToken,
                    onProgress: { progress = $0 },
                    onFinished: { loading = false },
                    onCookie: { store in
                        Task { await auth.capture(store: store, client: client) }
                    }
                )
                .overlay(alignment: .top) {
                    if loading {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(p.accent)
                    }
                }

                footer
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
                    loading = true
                    reloadToken = UUID()
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

// MARK: - WKWebView

struct MaiLoginWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID
    let onProgress: (Double) -> Void
    let onFinished: () -> Void
    let onCookie: (WKWebsiteDataStore) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        // Enables WebAuthn inside the web view. Requires WKAppBoundDomains
        // in Info.plist; navigation outside those domains is then blocked.
        cfg.limitsNavigationsToAppBoundDomains = true

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = safariUserAgent
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear

        context.coordinator.observe(web)
        context.coordinator.loaded = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loaded != url || context.coordinator.lastToken != reloadToken {
            context.coordinator.loaded = url
            context.coordinator.lastToken = reloadToken
            web.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MaiLoginWebView
        var loaded: URL?
        var lastToken: UUID?
        private var progressObs: NSKeyValueObservation?

        init(_ parent: MaiLoginWebView) {
            self.parent = parent
            self.lastToken = parent.reloadToken
        }

        func observe(_ web: WKWebView) {
            progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                self?.parent.onProgress(w.estimatedProgress)
            }
        }

        func stopObserving() {
            progressObs?.invalidate()
            progressObs = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onFinished()
            parent.onCookie(webView.configuration.websiteDataStore)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onFinished()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onFinished()
            let ns = error as NSError
            // -1022 App-Bound Domains refused a navigation outside the list.
            if ns.code == -1022 {
                print("[login] navigation blocked by App-Bound Domains:", webView.url?.host() ?? "?")
            }
        }

        // Allow the WebAuthn / passkey sheet to present over the web view.
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}