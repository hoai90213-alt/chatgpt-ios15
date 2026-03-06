import SwiftUI

struct MainView: View {
    @EnvironmentObject private var webViewManager: WebViewManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if !webViewManager.showWebLoginSheet {
                // Keep the web engine alive but visually hidden in native mode.
                WebViewContainer(webViewManager: webViewManager)
                    .ignoresSafeArea()
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if webViewManager.shouldShowSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                NativeChatShell(
                    messages: webViewManager.nativeMessages,
                    isComposerAvailable: webViewManager.isComposerAvailable,
                    isPageLoading: webViewManager.isPageLoading,
                    loadingProgress: webViewManager.loadingProgress,
                    canGoBack: webViewManager.canGoBack,
                    onBack: webViewManager.goBack,
                    onNewChat: webViewManager.startNewChat,
                    onReload: webViewManager.reload,
                    onOpenWeb: webViewManager.presentWebLogin,
                    onSend: webViewManager.sendNativeMessage
                )
                .transition(.opacity)
            }

            if !networkMonitor.isConnected {
                NetworkErrorBanner()
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: webViewManager.shouldShowSplash)
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isConnected)
        .sheet(isPresented: $webViewManager.showWebLoginSheet) {
            WebLoginSheet(webViewManager: webViewManager)
        }
    }
}

private struct NativeChatShell: View {
    let messages: [NativeChatMessage]
    let isComposerAvailable: Bool
    let isPageLoading: Bool
    let loadingProgress: Double
    let canGoBack: Bool
    let onBack: () -> Void
    let onNewChat: () -> Void
    let onReload: () -> Void
    let onOpenWeb: () -> Void
    let onSend: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            NativeHeaderBar(
                isPageLoading: isPageLoading,
                loadingProgress: loadingProgress,
                canGoBack: canGoBack,
                onBack: onBack,
                onNewChat: onNewChat,
                onReload: onReload,
                onOpenWeb: onOpenWeb
            )

            NativeMessagesView(
                messages: messages,
                isComposerAvailable: isComposerAvailable,
                onOpenWeb: onOpenWeb
            )

            NativeComposerBar(
                draft: $draft,
                isComposerAvailable: isComposerAvailable,
                onOpenWeb: onOpenWeb
            ) { text in
                onSend(text)
            }
        }
    }
}

private struct NativeHeaderBar: View {
    let isPageLoading: Bool
    let loadingProgress: Double
    let canGoBack: Bool
    let onBack: () -> Void
    let onNewChat: () -> Void
    let onReload: () -> Void
    let onOpenWeb: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                }
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)

                Spacer()

                Text("ChatGPT")
                    .font(.headline.weight(.semibold))

                Spacer()

                HStack(spacing: 14) {
                    Button(action: onOpenWeb) {
                        Image(systemName: "safari")
                            .font(.headline.weight(.semibold))
                    }

                    Button(action: onNewChat) {
                        Image(systemName: "plus.bubble")
                            .font(.headline.weight(.semibold))
                    }

                    Button(action: onReload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline.weight(.semibold))
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if isPageLoading {
                ProgressView(value: loadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.9))
                    .background(Color.white.opacity(0.1))
            }
        }
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

private struct NativeMessagesView: View {
    let messages: [NativeChatMessage]
    let isComposerAvailable: Bool
    let onOpenWeb: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

                        Text(isComposerAvailable ? "Syncing chat content..." : "Open Web once to log in.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))

                        if !isComposerAvailable {
                            Button("Open Web Login", action: onOpenWeb)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                NativeMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                    }
                }
            }
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: messages.last?.content) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct NativeMessageRow: View {
    let message: NativeChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }

            Text(message.content)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.green.opacity(0.24) : Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !isUser { Spacer(minLength: 44) }
        }
    }
}

private struct NativeComposerBar: View {
    @Binding var draft: String

    let isComposerAvailable: Bool
    let onOpenWeb: () -> Void
    let onSend: (String) -> Void

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !isComposerAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("Web login required for sending")
                    Spacer()
                    Button("Open", action: onOpenWeb)
                        .font(.subheadline.weight(.semibold))
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
            }

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Message ChatGPT")
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.top, 9)
                            .padding(.leading, 6)
                    }

                    TextEditor(text: $draft)
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(minHeight: 38, maxHeight: 92)
                        .padding(.horizontal, 2)
                        .disabled(!isComposerAvailable)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    let payload = trimmedDraft
                    guard !payload.isEmpty else { return }
                    draft = ""
                    onSend(payload)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .disabled(trimmedDraft.isEmpty || !isComposerAvailable)
                .opacity((trimmedDraft.isEmpty || !isComposerAvailable) ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

private struct WebLoginSheet: View {
    let webViewManager: WebViewManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            WebViewContainer(webViewManager: webViewManager)
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Web Login")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: webViewManager.reload) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
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
