import Foundation
import SpotifySDKCore

/// Manages token lifecycle — fetches, caches, and refreshes session tokens.
public actor SpotifyAuthService {
	public nonisolated let mode: SpotifyClientMode

	private let provider: any SpotifyAccessTokenProvider
	private let tokenStore: any SpotifyTokenStore
	private var cachedTokens: SpotifySessionTokens?

	package init(
		provider: any SpotifyAccessTokenProvider,
		tokenStore: any SpotifyTokenStore
	) {
		self.mode = provider.mode
		self.provider = provider
		self.tokenStore = tokenStore
	}

	public func currentSessionTokens(forceRefresh: Bool = false) async throws -> SpotifySessionTokens {
		if !forceRefresh, let cachedTokens, !cachedTokens.isExpired {
			return cachedTokens
		}

		if !forceRefresh, let storedTokens = try await tokenStore.loadTokens(), !storedTokens.isExpired {
			cachedTokens = storedTokens
			return storedTokens
		}

		let freshTokens = try await provider.fetchTokens()

		guard !freshTokens.isExpired else {
			throw SpotifySDKError.tokenExpired
		}

		cachedTokens = freshTokens
		try await tokenStore.saveTokens(freshTokens)
		return freshTokens
	}

	public func currentAccessToken(forceRefresh: Bool = false) async throws -> String {
		try await currentSessionTokens(forceRefresh: forceRefresh).accessToken.value
	}

	public func currentClientToken(forceRefresh: Bool = false) async throws -> String? {
		try await currentSessionTokens(forceRefresh: forceRefresh).clientToken?.value
	}

	public func clearCachedTokens() async throws {
		cachedTokens = nil
		try await tokenStore.clearTokens()
	}
}
