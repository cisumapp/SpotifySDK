import SwiftUI
import WebKit
import SpotifySDKCore

#if os(macOS)
public typealias PlatformViewRepresentable = NSViewRepresentable
#else
public typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// A WebView-based view that intercepts Spotify authentication tokens.
/// Ported from Daagify's working SpotifyWebView.swift logic.
public struct SpotifyTokenExtractorView: PlatformViewRepresentable {
    let mode: SpotifyAuthMode
    let onTokensExtracted: @MainActor (SpotifySessionTokens) -> Void

    public init(
        mode: SpotifyAuthMode,
        onTokensExtracted: @escaping @MainActor (SpotifySessionTokens) -> Void
    ) {
        self.mode = mode
        self.onTokensExtracted = onTokensExtracted
    }

    private var startURL: URL {
        switch mode {
        case .authenticated:
            return URL(string: "https://accounts.spotify.com/en/login?continue=https://open.spotify.com/")!
        case .anonymous:
            return URL(string: "https://open.spotify.com/")!
        }
    }

    // MARK: - Platform Bridge

    #if os(macOS)
    public func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView(with: startURL)
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    #else
    public func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView(with: startURL)
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
    #endif

    public func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, onTokensExtracted: onTokensExtracted)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let mode: SpotifyAuthMode
        let onTokensExtracted: (SpotifySessionTokens) -> Void

        private var extractedAccessToken: String?
        private var extractedAccessTokenExpiry: Date?
        private var extractedClientToken: String?
        private var extractedClientID: String?
        private var extractedWebPlayerCookie: String?
        
        private var hasUpgradedToken = false

        init(mode: SpotifyAuthMode, onTokensExtracted: @escaping (SpotifySessionTokens) -> Void) {
            self.mode = mode
            self.onTokensExtracted = onTokensExtracted
        }

        func makeWebView(with url: URL) -> WKWebView {
            let config = WKWebViewConfiguration()
            let contentController = WKUserContentController()

            // Inject the interceptor script
            let script = WKUserScript(
                source: spotifyTokenInterceptorJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            contentController.addUserScript(script)
            contentController.add(self, name: "spotifyTokenHandler")

            // Add resource blocking to speed up extraction
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "SpotifyFaster",
                encodedContentRuleList: spotifyContentBlockRules
            ) { list, error in
                if let list = list {
                    config.userContentController.add(list)
                }
            }

            config.userContentController = contentController

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
            webView.load(URLRequest(url: url))
            return webView
        }

        // MARK: - WKNavigationDelegate

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            captureWebPlayerCookie(from: webView)
        }

        // MARK: - WKScriptMessageHandler

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "spotifyTokenHandler",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let payload = body["payload"] as? [String: Any] else {
                return
            }

            switch type {
            case "ACCESS_TOKEN":
                if let token = payload["accessToken"] as? String ?? payload["access_token"] as? String {
                    // Update current state
                    self.extractedAccessToken = token

                    if let expirySeconds = payload["expiresIn"] as? Double {
                        self.extractedAccessTokenExpiry = Date().addingTimeInterval(expirySeconds)
                    } else if let expiryMs = payload["accessTokenExpirationTimestampMs"] as? Double {
                        self.extractedAccessTokenExpiry = Date(timeIntervalSince1970: expiryMs / 1000)
                    }

                    if let clientID = payload["clientId"] as? String ?? payload["client_id"] as? String {
                        self.extractedClientID = clientID
                    }
                    
                    // If we got this via the upgraded fetch, mark it
                    if payload["isUpgraded"] as? Bool == true {
                        self.hasUpgradedToken = true
                    }
                    
                    deliverCurrentTokens()
                }

            case "CLIENT_TOKEN":
                if let grantedToken = payload["granted_token"] as? [String: Any],
                   let token = grantedToken["token"] as? String {
                    self.extractedClientToken = token
                    
                    // Immediately trigger access token upgrade via TOTP (Crucial for Pathfinder)
                    Task {
                        let totpSource = SpotifyLiveTOTPSource()
                        if let totp = try? await totpSource.currentCode(at: Date()) {
                            await MainActor.run {
                                let js = """
                                fetch("https://open.spotify.com/api/token?reason=transport&productType=web-player&totp=\(totp.value)&totpVer=\(totp.version)")
                                    .then(r => r.json())
                                    .then(data => {
                                        if (data.accessToken) {
                                            data.isUpgraded = true;
                                            window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: data });
                                        }
                                    }).catch(console.error);
                                """
                                message.webView?.evaluateJavaScript(js)
                            }
                        }
                    }
                    deliverCurrentTokens()
                }

            case "DEBUG":
                if let msg = payload["msg"] as? String {
                    print("🟡 [SpotifyOAuth JS]: \(msg)")
                }

            default:
                break
            }
        }

        private func captureWebPlayerCookie(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }

                Task { @MainActor in
                    guard let cookie = cookies.first(where: { $0.name == "sp_t" })?.value else {
                        return
                    }

                    guard self.extractedWebPlayerCookie != cookie else {
                        return
                    }

                    self.extractedWebPlayerCookie = cookie
                    self.deliverCurrentTokens()
                }
            }
        }

        private func deliverCurrentTokens() {
            guard let accessToken = extractedAccessToken else { return }

            let tokens = SpotifySessionTokens(
                accessToken: SpotifyAccessToken(
                    value: accessToken,
                    expiresAt: extractedAccessTokenExpiry ?? Date().addingTimeInterval(3600)
                ),
                clientToken: extractedClientToken.map { SpotifyClientToken(value: $0) },
                clientID: extractedClientID,
                spotifyWebPlayerCookie: extractedWebPlayerCookie,
                isAnonymous: mode == .anonymous
            )

            print("🟢 [SpotifyOAuth] Streaming update. AccessToken: \(accessToken.prefix(10))... ClientToken: \(extractedClientToken?.prefix(10) ?? "NONE")... Upgraded: \(hasUpgradedToken)")

            onTokensExtracted(tokens)
        }
    }
}
