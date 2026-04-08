import Foundation
import SwiftUI
import SpotifySDKCore

// MARK: - Auth Mode

/// Determines the authentication flow used by SpotifyOAuth.
public enum SpotifyAuthMode: String, Sendable, Hashable {
    /// Authenticated flow — user logs into Spotify, gets access to user data + public data.
    case authenticated
    /// Anonymous flow — no login required, only public data accessible.
    case anonymous
}

// MARK: - Session State

/// Observable state for the SpotifyOAuth session.
public enum SpotifySessionState: Sendable, Equatable {
    case idle
    case extractingTokens
    case authenticated(SpotifySessionTokens)
    case refreshing
    case failed(String)
}

// MARK: - SpotifyOAuth Session Manager

/// Main entry point for Spotify authentication via WebView token extraction.
/// Manages token lifecycle including extraction, caching, and silent refresh.
@MainActor
@Observable
public final class SpotifyOAuthSession {
    public nonisolated let mode: SpotifyAuthMode

    public private(set) var state: SpotifySessionState = .idle
    public private(set) var tokens: SpotifySessionTokens?

    /// Whether the session has valid, non-expired tokens.
    public var isAuthenticated: Bool {
        guard let tokens else { return false }
        return !tokens.isExpired
    }

    /// Whether the token extractor view needs to be shown.
    public var needsWebView: Bool {
        switch state {
        case .idle, .failed:
            return true
        case .extractingTokens:
            return true
        case .authenticated, .refreshing:
            return false
        }
    }

    private let tokenStore: any SpotifyTokenStore
    private var refreshTask: Task<Void, Never>?
    private let refreshMargin: TimeInterval = 300 // 5 minutes before expiry

    public init(
        mode: SpotifyAuthMode,
        tokenStore: any SpotifyTokenStore = InMemorySpotifyTokenStore()
    ) {
        self.mode = mode
        self.tokenStore = tokenStore
    }

    deinit {
        // Task cancellation in deinit is limited by MainActor isolation in Swift 6.
        // We ensure tasks are properly cancelled during sign-out or session reset.
    }

    // MARK: - Public API

    /// Call this when the extractor view should begin extracting.
    public func beginExtraction() {
        state = .extractingTokens
    }

    /// Called by the token extractor view when tokens are captured.
    public func handleExtractedTokens(_ tokens: SpotifySessionTokens) {
        self.tokens = tokens
        self.state = .authenticated(tokens)
        Task {
            try? await tokenStore.saveTokens(tokens)
        }
        scheduleRefresh(for: tokens)
    }

    /// Attempt to restore tokens from cache on app launch.
    public func restoreFromCache() async {
        guard let cached = try? await tokenStore.loadTokens(), !cached.isExpired else {
            return
        }
        self.tokens = cached
        self.state = .authenticated(cached)
        scheduleRefresh(for: cached)
    }

    /// Force a token refresh (shows the webview briefly for silent refresh).
    public func refresh() {
        state = .refreshing
        // The silent refresh WebView will be shown at zero size
        // and will re-extract tokens using existing cookies
        state = .extractingTokens
    }

    /// Clear all tokens and reset session.
    public func signOut() async {
        refreshTask?.cancel()
        tokens = nil
        state = .idle
        try? await tokenStore.clearTokens()
    }

    /// Get valid tokens, refreshing if needed. Used by SpotifySDK internally.
    public func validTokens() async throws -> SpotifySessionTokens {
        if let tokens, !tokens.isExpired {
            return tokens
        }

        // Try cache
        if let cached = try? await tokenStore.loadTokens(), !cached.isExpired {
            self.tokens = cached
            return cached
        }

        throw SpotifySDKError.tokenExpired
    }

    // MARK: - Silent Refresh

    private func scheduleRefresh(for tokens: SpotifySessionTokens) {
        refreshTask?.cancel()

        let expiresAt = tokens.accessToken.expiresAt
        let refreshAt = expiresAt.addingTimeInterval(-refreshMargin)
        let delay = max(refreshAt.timeIntervalSinceNow, 10) // At least 10 seconds

        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.triggerSilentRefresh()
        }
    }

    private func triggerSilentRefresh() {
        if case .extractingTokens = state { return }
        state = .refreshing
        // Consumer should check `needsRefresh` and present a hidden extractor
        // The SpotifySDK auto-handles this via SpotifySilentRefreshView
        state = .extractingTokens
    }
}

// MARK: - Access Token Provider Conformance

/// Bridges SpotifyOAuthSession to the SpotifyAccessTokenProvider protocol
/// used internally by SpotifySDK's SpotifyAuthService.
package final class SpotifyOAuthTokenProvider: SpotifyAccessTokenProvider, @unchecked Sendable {
    package let mode: SpotifyClientMode
    private let session: SpotifyOAuthSession

    package init(mode: SpotifyClientMode, session: SpotifyOAuthSession) {
        self.mode = mode
        self.session = session
    }

    package func fetchTokens() async throws -> SpotifySessionTokens {
        try await session.validTokens()
    }
}

// MARK: - Silent Refresh View

/// A zero-size view that silently refreshes tokens using existing WKWebView cookies.
/// Embed this in your view hierarchy — it only activates when tokens need refreshing.
public struct SpotifySilentRefreshView: View {
    let session: SpotifyOAuthSession

    public init(session: SpotifyOAuthSession) {
        self.session = session
    }

    public var body: some View {
        Group {
            if case .refreshing = session.state {
                SpotifyTokenExtractorView(
                    mode: session.mode,
                    onTokensExtracted: { tokens in
                        session.handleExtractedTokens(tokens)
                    }
                )
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
    }
}
