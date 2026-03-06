import Foundation
import WebKit
import Combine
import UIKit

final class WebViewManager: NSObject, ObservableObject {
    @Published private(set) var isInitialLoadFinished: Bool = false
    @Published private(set) var isPageLoading: Bool = true
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var canGoBack: Bool = false

    let webView: WKWebView

    private static let sharedProcessPool = WKProcessPool()

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
        configuration.processPool = Self.sharedProcessPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(Self.nativeShellStyleScript())

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        configureWebView()
        configurePullToRefresh()
        bindWebViewState()
        bindNetworkState(networkMonitor)
        loadHomePage()
    }

    var shouldShowSplash: Bool {
        !isInitialLoadFinished
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func startNewChat() {
        loadHomePage()
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
        webView.allowsLinkPreview = false
        // Disable Safari-like edge-swipe navigation to feel less "web browser".
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.directionalLockEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    private func configurePullToRefresh() {
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    private func bindWebViewState() {
        webView.publisher(for: \.canGoBack, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canGoBack in
                self?.canGoBack = canGoBack
            }
            .store(in: &cancellables)

        webView.publisher(for: \.estimatedProgress, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.loadingProgress = progress
            }
            .store(in: &cancellables)
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

    private static func nativeShellStyleScript() -> WKUserScript {
        let source = """
        (function () {
          var styleId = 'ios-native-shell-style';

          function ensureViewport() {
            var meta = document.querySelector('meta[name="viewport"]');
            var value = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
            if (!meta) {
              meta = document.createElement('meta');
              meta.name = 'viewport';
              meta.content = value;
              document.head.appendChild(meta);
              return;
            }
            if (meta.content.indexOf('viewport-fit=cover') === -1) {
              meta.content = value;
            }
          }

          function pickVisibleComposerContainer() {
            var textareas = document.querySelectorAll('textarea');
            var bestTextArea = null;
            var bestBottom = -Infinity;

            for (var i = 0; i < textareas.length; i++) {
              var ta = textareas[i];
              var rect = ta.getBoundingClientRect();
              if (rect.width <= 0 || rect.height <= 0) { continue; }
              if (rect.bottom > bestBottom) {
                bestBottom = rect.bottom;
                bestTextArea = ta;
              }
            }

            if (!bestTextArea) { return null; }

            var current = bestTextArea;
            for (var level = 0; level < 8 && current; level++) {
              if (current.tagName === 'FORM') {
                return current;
              }
              current = current.parentElement;
            }

            return bestTextArea.parentElement;
          }

          function pinComposer() {
            var oldNode = document.querySelector('[data-ios-composer-pinned="1"]');
            if (oldNode) {
              oldNode.removeAttribute('data-ios-composer-pinned');
            }

            var composer = pickVisibleComposerContainer();
            if (composer) {
              composer.setAttribute('data-ios-composer-pinned', '1');
            }
          }

          function installStyle() {
            if (document.getElementById(styleId)) { return; }
            var style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
              :root { color-scheme: dark !important; }
              html, body {
                background: #000 !important;
                overscroll-behavior-y: none !important;
              }
              body {
                -webkit-overflow-scrolling: touch !important;
              }
              * { -webkit-tap-highlight-color: rgba(0, 0, 0, 0) !important; }
              header[role="banner"] { display: none !important; }
              [data-ios-composer-pinned="1"] {
                position: sticky !important;
                bottom: 0 !important;
                z-index: 999 !important;
                padding-bottom: max(env(safe-area-inset-bottom), 8px) !important;
                background: rgba(0, 0, 0, 0.9) !important;
                backdrop-filter: blur(14px) !important;
              }
            `;
            document.head.appendChild(style);
          }

          function installBehavior() {
            pinComposer();
            var observer = new MutationObserver(function () {
              pinComposer();
            });
            observer.observe(document.documentElement, { childList: true, subtree: true });
            window.addEventListener('resize', pinComposer);
            setInterval(pinComposer, 1400);
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function () {
              ensureViewport();
              installStyle();
              installBehavior();
            }, { once: true });
          } else {
            ensureViewport();
            installStyle();
            installBehavior();
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private func shouldOpenInsideApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let allowedHosts = [
            "chatgpt.com",
            "chat.openai.com",
            "openai.com",
            "auth.openai.com",
            "oaistatic.com",
            "cdn.oaistatic.com"
        ]
        return allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }
}

extension WebViewManager: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isPageLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }

        isPageLoading = false

        if !isInitialLoadFinished {
            isInitialLoadFinished = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        isPageLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        isPageLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if shouldOpenInsideApp(url) {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if shouldOpenInsideApp(url) {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageLoading = true
        webView.reload()
    }
}
