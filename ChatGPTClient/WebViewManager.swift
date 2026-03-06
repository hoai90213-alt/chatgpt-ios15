import Foundation
import WebKit
import Combine
import UIKit

struct NativeChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
        case system
    }

    let id: String
    let role: Role
    let content: String
}

final class WebViewManager: NSObject, ObservableObject {
    @Published private(set) var isInitialLoadFinished: Bool = false
    @Published private(set) var isPageLoading: Bool = true
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var nativeMessages: [NativeChatMessage] = []
    @Published private(set) var isComposerAvailable: Bool = false
    @Published var showWebLoginSheet: Bool = false

    let webView: WKWebView

    private static let sharedProcessPool = WKProcessPool()

    private let refreshControl = UIRefreshControl()
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectionState: Bool = true
    private var syncTimer: Timer?
    private var isSnapshotInFlight: Bool = false

    private struct DOMSnapshot: Decodable {
        let hasComposer: Bool
        let messages: [DOMMessage]
    }

    private struct DOMMessage: Decodable {
        let role: String
        let content: String
    }

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
        startNativeSyncLoop()
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

    func presentWebLogin() {
        showWebLoginSheet = true
    }

    func sendNativeMessage(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let promptLiteral = Self.jsStringLiteral(prompt)
        let script = Self.sendMessageScript(promptLiteral: promptLiteral)

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }

            if let status = result as? String, status == "no_textarea" {
                DispatchQueue.main.async {
                    self.isComposerAvailable = false
                    self.showWebLoginSheet = true
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.syncNativeSnapshot()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.syncNativeSnapshot()
            }
        }
    }

    func loadHomePage() {
        guard let url = URL(string: "https://chatgpt.com") else { return }
        let request = URLRequest(url: url)
        isPageLoading = true
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
        webView.scrollView.isDirectionalLockEnabled = true
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

    private func startNativeSyncLoop() {
        guard syncTimer == nil else { return }

        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.syncNativeSnapshot()
        }

        if let syncTimer {
            RunLoop.main.add(syncTimer, forMode: .common)
        }

        syncNativeSnapshot()
    }

    private func syncNativeSnapshot() {
        guard !isSnapshotInFlight else { return }
        isSnapshotInFlight = true

        webView.evaluateJavaScript(Self.nativeSnapshotScript) { [weak self] result, _ in
            guard let self else { return }

            defer {
                self.isSnapshotInFlight = false
            }

            guard let json = result as? String, let data = json.data(using: .utf8) else { return }
            guard let snapshot = try? JSONDecoder().decode(DOMSnapshot.self, from: data) else { return }

            let mappedMessages = Self.mapSnapshotToNativeMessages(snapshot.messages)

            DispatchQueue.main.async {
                self.isComposerAvailable = snapshot.hasComposer
                self.nativeMessages = mappedMessages

                if snapshot.hasComposer && self.showWebLoginSheet {
                    self.showWebLoginSheet = false
                }
            }
        }
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
            `;
            document.head.appendChild(style);
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function () {
              ensureViewport();
              installStyle();
            }, { once: true });
          } else {
            ensureViewport();
            installStyle();
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static var nativeSnapshotScript: String {
        """
        (function () {
          function cleanText(value) {
            if (!value) { return ''; }
            return String(value)
              .replace(/\\u00a0/g, ' ')
              .replace(/\\n{3,}/g, '\\n\\n')
              .trim();
          }

          function detectRole(node, fallbackRole) {
            if (!node) { return fallbackRole || 'assistant'; }
            var role = node.getAttribute && node.getAttribute('data-message-author-role');
            if (role) { return role; }

            var testId = node.getAttribute && node.getAttribute('data-testid');
            if (testId) {
              if (testId.indexOf('assistant') !== -1) { return 'assistant'; }
              if (testId.indexOf('user') !== -1) { return 'user'; }
            }

            var walker = node.parentElement;
            for (var i = 0; i < 6 && walker; i++) {
              role = walker.getAttribute && walker.getAttribute('data-message-author-role');
              if (role) { return role; }
              walker = walker.parentElement;
            }
            return fallbackRole || 'assistant';
          }

          var messages = [];
          var seen = new Set();
          var nodes = document.querySelectorAll('[data-message-author-role], [data-testid^=\"conversation-turn-\"]');
          for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var role = detectRole(node, 'assistant');
            var content = cleanText(node.innerText || node.textContent || '');
            if (!content) { continue; }
            if (seen.has(content)) { continue; }
            seen.add(content);
            messages.push({ role: role, content: content });
          }

          if (messages.length === 0) {
            var fallbackBlocks = document.querySelectorAll('main article, main [class*=\"markdown\"], main [data-testid*=\"conversation\"]');
            for (var j = 0; j < fallbackBlocks.length; j++) {
              var block = fallbackBlocks[j];
              var fallbackContent = cleanText(block.innerText || block.textContent || '');
              if (!fallbackContent) { continue; }
              if (seen.has(fallbackContent)) { continue; }
              seen.add(fallbackContent);
              messages.push({
                role: detectRole(block, j % 2 === 0 ? 'assistant' : 'user'),
                content: fallbackContent
              });
            }
          }

          var hasComposer = !!document.querySelector('textarea, [contenteditable=\"true\"]');
          return JSON.stringify({
            hasComposer: hasComposer,
            messages: messages.slice(-80)
          });
        })();
        """
    }

    private static func sendMessageScript(promptLiteral: String) -> String {
        """
        (function () {
          var textarea = document.querySelector('textarea');
          var prompt = \(promptLiteral);
          if (textarea) {
            textarea.focus();
            textarea.value = prompt;
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
            textarea.dispatchEvent(new Event('change', { bubbles: true }));
          } else {
            var editable = document.querySelector('[contenteditable=\"true\"]');
            if (!editable) { return 'no_textarea'; }
            editable.focus();
            editable.textContent = prompt;
            editable.dispatchEvent(new Event('input', { bubbles: true }));
            editable.dispatchEvent(new Event('change', { bubbles: true }));
          }

          var form = textarea ? textarea.closest('form') : null;
          var button = form ? form.querySelector('button[type=\"submit\"]:not([disabled])') : null;
          if (!button) {
            button = document.querySelector('button[data-testid=\"send-button\"]:not([disabled])');
          }

          if (button) {
            button.click();
            return 'sent';
          }

          var enterEvent = new KeyboardEvent('keydown', {
            key: 'Enter',
            code: 'Enter',
            keyCode: 13,
            which: 13,
            bubbles: true
          });
          textarea.dispatchEvent(enterEvent);
          return 'enter';
        })();
        """
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func mapSnapshotToNativeMessages(_ messages: [DOMMessage]) -> [NativeChatMessage] {
        messages.enumerated().compactMap { index, message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }

            let role = NativeChatMessage.Role(rawValue: message.role) ?? .assistant
            return NativeChatMessage(id: "msg-\(index)-\(role.rawValue)", role: role, content: content)
        }
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

    deinit {
        syncTimer?.invalidate()
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

        if showWebLoginSheet {
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
            if showWebLoginSheet || shouldOpenInsideApp(url) {
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
