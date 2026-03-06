import SwiftUI

struct MainView: View {
    @EnvironmentObject private var webViewManager: WebViewManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            WebViewContainer(webViewManager: webViewManager)
                .ignoresSafeArea()
                .opacity(webViewManager.shouldShowSplash ? 0 : 1)

            if webViewManager.shouldShowSplash {
                // Show splash until the first successful page load.
                SplashView()
                    .transition(.opacity)
            }

            if !networkMonitor.isConnected {
                // Lightweight network warning; auto-hides when connection returns.
                NetworkErrorBanner()
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: webViewManager.shouldShowSplash)
        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "message.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white)
            Text("ChatGPT")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct NetworkErrorBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
            Text("No internet connection")
                .foregroundColor(.white)
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.red.opacity(0.9))
        .clipShape(Capsule())
    }
}
