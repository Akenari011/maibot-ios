//
//  LoginView.swift
//  MaiBot
//
//  Sign-in runs in a WKWebView configured for WebAuthn (App-Bound Domains)
//  and a Safari user agent, so the hardware-key row works and GitHub renders.
//

import SwiftUI
import WebKit

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
        VStack(spacing: 0) {
            header
            MaiLoginWebView(
                url: client.baseURL,
                reloadToken: reloadToken,
                onProgress: { progress = $0 },
                onFinished: { loading = false },
                onCookie: { store in Task { await auth.capture(store: store, client: client) } }
            )
            .overlay(alignment: .top) {
                if loading { ProgressView(value: progress).tint(p.orange) }
            }
            footer
        }
        .background(p.bg)
        .alert("修改服务器地址", isPresented: $editingHost) {
            TextField("https://maibot.example.com", text: $hostDraft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let u = URL(string: hostDraft.trimmingCharacters(in: .whitespaces)), u.scheme != nil, u.host != nil {
                    client.baseURL = u; loading = true; reloadToken = UUID()
                }
            }
        } message: { Text("填写面板的完整地址") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(p.orange.opacity(0.14))
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(p.orange)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("MaiBot 面板").font(.system(size: 17, weight: .bold)).foregroundStyle(p.text)
                Text(client.baseURL.host() ?? "").font(.system(size: 12)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            Button {
                hostDraft = client.baseURL.absoluteString; editingHost = true
            } label: {
                Image(systemName: "server.rack").font(.system(size: 16)).foregroundStyle(p.text)
                    .frame(width: 38, height: 38)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(p.separator) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(p.card)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill").font(.system(size: 11))
            Text("登录在系统网页视图中完成，凭据不经过本应用").font(.system(size: 11))
        }
        .foregroundStyle(p.textSecondary)
        .padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(p.card)
        .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 1) }
    }
}

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

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.stopObserving() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MaiLoginWebView
        var loaded: URL?
        var lastToken: UUID?
        private var progressObs: NSKeyValueObservation?

        init(_ parent: MaiLoginWebView) { self.parent = parent; self.lastToken = parent.reloadToken }

        func observe(_ web: WKWebView) {
            progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                self?.parent.onProgress(w.estimatedProgress)
            }
        }
        func stopObserving() { progressObs?.invalidate(); progressObs = nil }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onFinished()
            parent.onCookie(webView.configuration.websiteDataStore)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onFinished() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onFinished()
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.grant) }
    }
}