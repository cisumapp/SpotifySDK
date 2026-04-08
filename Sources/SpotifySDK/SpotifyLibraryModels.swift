import Foundation
import SpotifySDKCore

public struct SpotifyLibraryOption: Sendable, Hashable {
	public var id: String
	public var name: String

	public init(id: String, name: String) {
		self.id = id
		self.name = name
	}
}

public struct SpotifyLibraryPageInfo: Sendable, Hashable {
	public var limit: Int?
	public var offset: Int?

	public init(limit: Int? = nil, offset: Int? = nil) {
		self.limit = limit
		self.offset = offset
	}
}

public struct SpotifyLibraryPage: Sendable, Hashable {
	public var pageInfo: SpotifyLibraryPageInfo
	public var availableFilters: [SpotifyLibraryOption]
	public var availableSortOrders: [SpotifyLibraryOption]
	public var selectedFilters: [SpotifyLibraryOption]
	public var selectedSortOrder: SpotifyLibraryOption?
	public var totalCount: Int?
	public var playlists: [SpotifyLibraryPlaylistSummary]
	public var likedSongs: SpotifyLibraryPlaylistSummary?

	public init(
		pageInfo: SpotifyLibraryPageInfo = .init(),
		availableFilters: [SpotifyLibraryOption] = [],
		availableSortOrders: [SpotifyLibraryOption] = [],
		selectedFilters: [SpotifyLibraryOption] = [],
		selectedSortOrder: SpotifyLibraryOption? = nil,
		totalCount: Int? = nil,
		playlists: [SpotifyLibraryPlaylistSummary] = [],
		likedSongs: SpotifyLibraryPlaylistSummary? = nil
	) {
		self.pageInfo = pageInfo
		self.availableFilters = availableFilters
		self.availableSortOrders = availableSortOrders
		self.selectedFilters = selectedFilters
		self.selectedSortOrder = selectedSortOrder
		self.totalCount = totalCount
		self.playlists = playlists
		self.likedSongs = likedSongs
	}
}

public struct SpotifyLikedSongEntry: Sendable, Hashable {
	public var addedAt: Date?
	public var track: SpotifyTrack

	public init(addedAt: Date? = nil, track: SpotifyTrack) {
		self.addedAt = addedAt
		self.track = track
	}
}

public struct SpotifyLikedSongsPage: Sendable, Hashable {
	public var pageInfo: SpotifyLibraryPageInfo
	public var totalCount: Int?
	public var items: [SpotifyLikedSongEntry]

	public init(
		pageInfo: SpotifyLibraryPageInfo = .init(),
		totalCount: Int? = nil,
		items: [SpotifyLikedSongEntry] = []
	) {
		self.pageInfo = pageInfo
		self.totalCount = totalCount
		self.items = items
	}

	public var tracks: [SpotifyTrack] {
		items.map(\.track)
	}
}

struct SpotifyLibraryV3Response: Decodable {
	let data: SpotifyLibraryV3Data?

	func toDomain() -> SpotifyLibraryPage {
		data?.me?.libraryV3?.toDomain() ?? SpotifyLibraryPage()
	}
}

struct SpotifyLibraryV3Data: Decodable {
	let me: SpotifyLibraryV3Me?
}

struct SpotifyLibraryV3Me: Decodable {
	let libraryV3: SpotifyLibraryV3PagePayload?
}

struct SpotifyLibraryV3PagePayload: Decodable {
	let availableFilters: [SpotifyLibraryV3OptionPayload]?
	let availableSortOrders: [SpotifyLibraryV3OptionPayload]?
	let breadcrumbs: [SpotifyLibraryBreadcrumbPayload]?
	let items: [SpotifyLibraryV3ItemPayload]?
	let pagingInfo: SpotifyLibraryPageInfoPayload?
	let selectedFilters: [SpotifyLibraryV3OptionPayload]?
	let selectedSortOrder: SpotifyLibraryV3OptionPayload?
	let totalCount: Int?

	func toDomain() -> SpotifyLibraryPage {
		let playlistItems = items ?? []
		let mappedPlaylists = playlistItems.compactMap { item in
			item.item?.data?.playlistSummary(addedAt: item.addedAt?.dateValue)
		}
		let likedSongs = playlistItems.compactMap { item in
			item.item?.data?.likedSongsSummary(addedAt: item.addedAt?.dateValue)
		}.first

		return SpotifyLibraryPage(
			pageInfo: pagingInfo?.toDomain() ?? .init(),
			availableFilters: (availableFilters ?? []).map { $0.toDomain() },
			availableSortOrders: (availableSortOrders ?? []).map { $0.toDomain() },
			selectedFilters: (selectedFilters ?? []).map { $0.toDomain() },
			selectedSortOrder: selectedSortOrder?.toDomain(),
			totalCount: totalCount,
			playlists: deduplicatePlaylists(mappedPlaylists),
			likedSongs: likedSongs
		)
	}

	private func deduplicatePlaylists(_ playlists: [SpotifyLibraryPlaylistSummary]) -> [SpotifyLibraryPlaylistSummary] {
		var seen = Set<String>()
		var ordered: [SpotifyLibraryPlaylistSummary] = []

		for playlist in playlists {
			if seen.insert(playlist.uri).inserted {
				ordered.append(playlist)
			}
		}

		return ordered
	}
}

struct SpotifyLibraryV3ItemPayload: Decodable {
	let addedAt: SpotifyTimestampPayload?
	let depth: Int?
	let item: SpotifyLibraryV3ItemWrapper?
	let pinnable: Bool?
	let pinned: Bool?
	let playedAt: SpotifyTimestampPayload?
}

struct SpotifyLibraryV3ItemWrapper: Decodable {
	let typename: String?
	let uri: String?
	let data: SpotifyLibraryV3ItemData?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case uri = "_uri"
		case data
	}
}

struct SpotifyLibraryV3ItemData: Decodable {
	let typename: String?
	let name: String?
	let description: String?
	let format: String?
	let images: SpotifyLibraryV3Images?
	let image: SpotifyLibraryV3PseudoPlaylistImage?
	let ownerV2: SpotifyLibraryV3OwnerContainer?
	let revisionId: String?
	let uri: String?
	let count: Int?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case name
		case description
		case format
		case images
		case image
		case ownerV2
		case revisionId
		case uri
		case count
	}

	func playlistSummary(addedAt: Date? = nil) -> SpotifyLibraryPlaylistSummary? {
		guard typename == "Playlist" else { return nil }

		let imageURL = images?.items.first(where: { $0.targetName?.lowercased() == "default" })?.url
			?? images?.items.first?.url

		let ownerName = ownerV2?.data?.displayName ?? ownerV2?.data?.username
		let uriValue = uri ?? ""
		let nameValue = name ?? uriValue

		Logger.log("SpotifyLibraryV3ItemData: Decoded playlist summary. Name: '\(nameValue)', Typename: '\(typename ?? "nil")', URI: \(uriValue)")

		return SpotifyLibraryPlaylistSummary(
			uri: uriValue,
			name: nameValue,
			description: description,
			ownerUsername: ownerV2?.data?.username,
			ownerDisplayName: ownerName,
			artworkURL: imageURL.flatMap(URL.init(string:)),
			isPublic: nil,
			timestamp: addedAt,
			format: format,
			revision: revisionId,
			trackCount: count
		)
	}

	func likedSongsSummary(addedAt: Date? = nil) -> SpotifyLibraryPlaylistSummary? {
		guard typename == "PseudoPlaylist" else { return nil }
		guard uri == "spotify:collection:tracks" || name?.localizedCaseInsensitiveCompare("Liked Songs") == .orderedSame else {
			return nil
		}

		let imageURL = image?.sources.first(where: { $0.targetName?.lowercased() == "default" })?.url
			?? image?.sources.first?.url

		let uriValue = uri ?? "spotify:collection:tracks"

		return SpotifyLibraryPlaylistSummary(
			uri: uriValue,
			name: name ?? "Liked Songs",
			description: description,
			ownerUsername: ownerV2?.data?.username,
			ownerDisplayName: ownerV2?.data?.displayName,
			artworkURL: imageURL.flatMap(URL.init(string:)),
			isPublic: nil,
			timestamp: addedAt,
			format: format,
			revision: revisionId,
			trackCount: count
		)
	}
}

struct SpotifyLibraryV3OptionPayload: Decodable {
	let id: String
	let name: String

	func toDomain() -> SpotifyLibraryOption {
		SpotifyLibraryOption(id: id, name: name)
	}
}

struct SpotifyLibraryBreadcrumbPayload: Decodable {
	let id: String?
	let name: String?
	let uri: String?
}

struct SpotifyLibraryPageInfoPayload: Decodable {
	let limit: Int?
	let offset: Int?

	func toDomain() -> SpotifyLibraryPageInfo {
		SpotifyLibraryPageInfo(limit: limit, offset: offset)
	}
}

struct SpotifyLibraryV3Images: Decodable {
	let items: [SpotifyLibraryV3ImageItem]
}

struct SpotifyLibraryV3ImageItem: Decodable {
	let targetName: String?
	let url: String?
	let width: Int?
	let height: Int?
}

struct SpotifyLibraryV3PseudoPlaylistImage: Decodable {
	let sources: [SpotifyLibraryV3ImageItem]
}

struct SpotifyLibraryV3OwnerContainer: Decodable {
	let data: SpotifyLibraryV3OwnerData?
}

struct SpotifyLibraryV3OwnerData: Decodable {
	let typename: String?
	let name: String?
	let username: String?
	let uri: String?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case name
		case username
		case uri
	}

	var displayName: String? {
		name ?? username
	}
}

struct SpotifyTimestampPayload: Decodable {
	let isoString: String?

	var dateValue: Date? {
		parseSpotifyLibraryTimestamp(isoString)
	}
}

struct SpotifyUserLibraryTracksResponse: Decodable {
	let data: SpotifyUserLibraryTracksData?

	func toDomain() -> SpotifyLikedSongsPage {
		data?.me?.library?.tracks?.toDomain() ?? SpotifyLikedSongsPage()
	}
}

struct SpotifyUserLibraryTracksData: Decodable {
	let me: SpotifyUserLibraryTracksMe?
}

struct SpotifyUserLibraryTracksMe: Decodable {
	let library: SpotifyUserLibraryTracksLibrary?
}

struct SpotifyUserLibraryTracksLibrary: Decodable {
	let tracks: SpotifyUserLibraryTracksPage?
}

struct SpotifyUserLibraryTracksPage: Decodable {
	let typename: String?
	let items: [SpotifyUserLibraryTrackResponse]?
	let pagingInfo: SpotifyLibraryPageInfoPayload?
	let totalCount: Int?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case items
		case pagingInfo
		case totalCount
	}

	func toDomain() -> SpotifyLikedSongsPage {
		let pageItems = (items ?? []).compactMap { $0.toDomain() }
		return SpotifyLikedSongsPage(
			pageInfo: pagingInfo?.toDomain() ?? .init(),
			totalCount: totalCount,
			items: pageItems
		)
	}
}

struct SpotifyUserLibraryTrackResponse: Decodable {
	let typename: String?
	let addedAt: SpotifyTimestampPayload?
	let track: SpotifyUserLibraryTrackWrapper?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case addedAt
		case track
	}

	func toDomain() -> SpotifyLikedSongEntry? {
		guard let trackData = track?.data else {
			Logger.log("SpotifyUserLibraryTrackResponse: Missing track data for item")
			return nil
		}
		
		let trackModel = trackData.toDomain(fallbackURI: track?.uri)
		return SpotifyLikedSongEntry(
			addedAt: parseSpotifyLibraryTimestamp(addedAt?.isoString),
			track: trackModel
		)
	}
}

struct SpotifyUserLibraryTrackWrapper: Decodable {
	let uri: String?
	let data: PathfinderTrackData?

	private enum CodingKeys: String, CodingKey {
		case uri = "_uri"
		case data
	}
}

private func parseSpotifyLibraryTimestamp(_ value: String?) -> Date? {
	guard let value, !value.isEmpty else { return nil }

	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	if let date = formatter.date(from: value) {
		return date
	}

	formatter.formatOptions = [.withInternetDateTime]
	return formatter.date(from: value)
}
