import Foundation
import SpotifySDKCore

public struct SpotifySearchSuggestion: Sendable, Hashable {
	public var title: String
	public var uri: String
	public var typeName: String?

	public init(title: String, uri: String, typeName: String? = nil) {
		self.title = title
		self.uri = uri
		self.typeName = typeName
	}
}

public extension SpotifySearchResults {
	var trackURIs: [String] {
		tracks?.items.map(\.uri) ?? []
	}

	var artistURIs: [String] {
		artists?.items.map(\.uri) ?? []
	}

	var albumURIs: [String] {
		albums?.items.map(\.uri) ?? []
	}

	var playlistURIs: [String] {
		playlists?.items.map(\.uri) ?? []
	}
}

public struct SpotifySearchClient: Sendable {
	private let pathfinder: SpotifyPathfinderClient

	public init(pathfinder: SpotifyPathfinderClient) {
		self.pathfinder = pathfinder
	}

	public func search(
		_ searchText: String,
		limit: Int = 10,
		offset: Int = 0,
		numberOfTopResults: Int = 5,
		includeAudiobooks: Bool = true,
		includeArtistHasConcertsField: Bool = false,
		includePreReleases: Bool = true,
		includeAuthors: Bool = false,
		includeEpisodeContentRatingsV2: Bool = false
	) async throws -> SpotifySearchResults {
		try await pathfinder.search(
			searchText,
			limit: limit,
			offset: offset,
			numberOfTopResults: numberOfTopResults,
			includeAudiobooks: includeAudiobooks,
			includeArtistHasConcertsField: includeArtistHasConcertsField,
			includePreReleases: includePreReleases,
			includeAuthors: includeAuthors,
			includeEpisodeContentRatingsV2: includeEpisodeContentRatingsV2
		)
	}

	public func searchSuggestions(
		_ searchText: String,
		limit: Int = 30,
		numberOfTopResults: Int = 30,
		offset: Int = 0,
		includeAuthors: Bool = false,
		includeEpisodeContentRatingsV2: Bool = false
	) async throws -> [SpotifySearchSuggestion] {
		let variables: [String: Any] = [
			"query": searchText,
			"limit": limit,
			"numberOfTopResults": numberOfTopResults,
			"offset": offset,
			"includeAuthors": includeAuthors,
			"includeEpisodeContentRatingsV2": includeEpisodeContentRatingsV2
		]

        let data = try await pathfinder.performQuery(operation: .searchSuggestionsQuery, variables: variables)
		let response = try JSONDecoder().decode(PathfinderSearchSuggestionsResponse.self, from: data)
		return response.toDomain()
	}

	public func track(id: String) async throws -> SpotifyTrack {
		try await track(uri: "spotify:track:\(id)")
	}

	public func track(uri: String) async throws -> SpotifyTrack {
		try await pathfinder.fetchTrack(uri: uri)
	}
}
