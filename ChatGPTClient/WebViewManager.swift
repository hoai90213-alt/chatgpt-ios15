import Foundation
import WebKit
import Combine
import UIKit

final class WebViewManager: NSObject, ObservableObject {
    @Published private(set) var isInitialLoadFinished: Bool = false

    let webView: WKWebView

    private let refreshControl = UIRefreshControl()
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectionState: Bool = true

    override init() {
        fatalError("Use init(networkMonitor:) instead.")
    }

    init(networkMonitor: NetworkMonitor) {
        let configuration = WKWebViewConfiguration()
        // Use default data store so ChatGPT login cookies/local storage persist.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptEnabled = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        configureWebView()
        configurePullToRefresh()
        bindNetworkState(networkMonitor)
        loadHomePage()
    }

    var shouldShowSplash: Bool {
        !isInitialLoadFinished
    }

    func reload() {
        webView.reload()
    }

    func loadHomePage() {
        guard let url = URL(string: "https://chatgpt.com") else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.alwaysBounceVertical = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    private func configurePullToRefresh() {
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    private func bindNetworkState(_ monitor: NetworkMonitor) {
        monitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self else { return }

                if isConnected && !self.lastConnectionState {
                    self.reload()
                }

                self.lastConnectionState = isConnected
            }
            .store(in: &cancellables)
    }

    @objc private func handlePullToRefresh() {
        reload()
    }
}

extension WebViewManager: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }

        if !isInitialLoadFinished {
            isInitialLoadFinished = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
