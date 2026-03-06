import SwiftUI

@main
struct ChatGPTClientApp: App {
    @StateObject private var networkMonitor: NetworkMonitor
    @StateObject private var webViewManager: WebViewManager

    init() {
        let monitor = NetworkMonitor()
        _networkMonitor = StateObject(wrappedValue: monitor)
        _webViewManager = StateObject(wrappedValue: WebViewManager(networkMonitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(networkMonitor)
                .environmentObject(webViewManager)
        }
    }
}
