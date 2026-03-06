import SwiftUI

struct MainView: View {
    @EnvironmentObject private var webViewManager: WebViewManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            WebViewContainer(webViewManager: webViewManager)
                .ignoresSafeArea(.container, edges: .bottom)
                .safeAreaInset(edge: .top, spacing: 0) {
                    NativeTopBar(webViewManager: webViewManager)
                }
                .opacity(webViewManager.shouldShowSplash ? 0 : 1)

            if webViewManager.shouldShowSplash {
                // Show splash until the first successful page load.
                SplashView()
                    .transition(.opacity)
            }

            if !networkMonitor.isConnected {
                // Lightweight network warning; auto-hides when connection returns.
                NetworkErrorBanner()
                    .padding(.top, 70)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: webViewManager.shouldShowSplash)
        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
    }
}

private struct NativeTopBar: View {
    @ObservedObject var webViewManager: WebViewManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: webViewManager.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                }
                .disabled(!webViewManager.canGoBack)
                .opacity(webViewManager.canGoBack ? 1 : 0.35)

                Spacer()

                Text("ChatGPT")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 14) {
                    Button(action: webViewManager.startNewChat) {
                        Image(systemName: "plus.bubble")
                            .font(.headline.weight(.semibold))
                    }

                    Button(action: webViewManager.reload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline.weight(.semibold))
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 52)

            if webViewManager.isPageLoading {
                ProgressView(value: webViewManager.loadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.85))
                    .background(Color.white.opacity(0.1))
            }
        }
        .background(Color.black.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
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
