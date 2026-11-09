import SwiftUI
import WebKit

struct CustomPluginWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.loadHTMLString(html, baseURL: baseURL)
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
