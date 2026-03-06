import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    init(webViewManager: WebViewManager) {
        self.webView = webViewManager.webView
    }

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Keep one persistent WKWebView instance for the whole app session.
    }
}
