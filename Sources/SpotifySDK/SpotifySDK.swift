@_exported import SpotifySDKCore
@_exported import SpotifyOAuth
import Foundation

@MainActor
public final class SpotifySDK {
	public let mode: SpotifyAuthMode
	public let session: SpotifyOAuthSession
	public let auth: SpotifyAuthService
	public let pathfinder: SpotifyPathfinderClient
	public let account: SpotifyAccountClient
	public let search: SpotifySearchClient
	public let playlists: SpotifyPlaylistClient

	/// Initialize the SpotifySDK with a SpotifyOAuth session.
	/// The session handles token extraction and lifecycle via WebView.
	public init(
		session: SpotifyOAuthSession,
		transport: any SpotifyTransport = URLSessionSpotifyTransport(),
		tokenStore: any SpotifyTokenStore = InMemorySpotifyTokenStore()
	) {
		self.mode = session.mode
		self.session = session

		let clientMode: SpotifyClientMode = session.mode == .authenticated ? .privateWebPlayer : .publicWebPlayer

		self.auth = SpotifyAuthService(
			provider: SpotifyOAuthTokenProvider(mode: clientMode, session: session),
			tokenStore: tokenStore
		)

		self.pathfinder = SpotifyPathfinderClient(auth: self.auth, transport: transport)
		self.account = SpotifyAccountClient(pathfinder: self.pathfinder, auth: self.auth, transport: transport)
		self.search = SpotifySearchClient(pathfinder: self.pathfinder)
		self.playlists = SpotifyPlaylistClient(pathfinder: self.pathfinder)
	}

	/// Convenience initializer that creates a session internally.
	public convenience init(
		mode: SpotifyAuthMode,
		transport: any SpotifyTransport = URLSessionSpotifyTransport(),
		tokenStore: any SpotifyTokenStore = InMemorySpotifyTokenStore()
	) {
		let session = SpotifyOAuthSession(mode: mode, tokenStore: tokenStore)
		self.init(session: session, transport: transport, tokenStore: tokenStore)
	}
}