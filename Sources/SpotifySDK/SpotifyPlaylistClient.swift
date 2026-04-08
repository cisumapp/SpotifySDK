import Foundation
import SpotifySDKCore

public struct SpotifyPlaylistClient: Sendable {
	private let pathfinder: SpotifyPathfinderClient

	public init(pathfinder: SpotifyPathfinderClient) {
		self.pathfinder = pathfinder
	}

	public func details(id: String) async throws -> SpotifyPlaylist {
		try await details(uri: "spotify:playlist:\(id)")
	}

	public func details(uri: String, offset: Int = 0, limit: Int = 50) async throws -> SpotifyPlaylist {
		try await pathfinder.fetchPlaylistContents(uri: uri, offset: offset, limit: limit)
	}
}
