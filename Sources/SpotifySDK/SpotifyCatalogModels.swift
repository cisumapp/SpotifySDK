import Foundation
import SpotifySDKCore

// MARK: - Domain Models

public struct SpotifyImage: Sendable, Hashable {
	public var url: URL
	public var width: Int?
	public var height: Int?

	public init(url: URL, width: Int? = nil, height: Int? = nil) {
		self.url = url
		self.width = width
		self.height = height
	}
}

public struct SpotifyPaging<Item: Sendable & Hashable>: Sendable, Hashable {
	public var href: URL?
	public var items: [Item]
	public var limit: Int?
	public var next: URL?
	public var offset: Int?
	public var previous: URL?
	public var total: Int?

	public init(
		href: URL? = nil,
		items: [Item] = [],
		limit: Int? = nil,
		next: URL? = nil,
		offset: Int? = nil,
		previous: URL? = nil,
		total: Int? = nil
	) {
		self.href = href
		self.items = items
		self.limit = limit
		self.next = next
		self.offset = offset
		self.previous = previous
		self.total = total
	}
}

public struct SpotifyArtist: Sendable, Hashable {
	public var id: String
	public var name: String
	public var href: URL?
	public var uri: String
	public var images: [SpotifyImage]
	public var genres: [String]
	public var popularity: Int?

	public init(
		id: String,
		name: String,
		href: URL? = nil,
		uri: String = "",
		images: [SpotifyImage] = [],
		genres: [String] = [],
		popularity: Int? = nil
	) {
		self.id = id
		self.name = name
		self.href = href
		self.uri = uri
		self.images = images
		self.genres = genres
		self.popularity = popularity
	}
}

public struct SpotifyAlbum: Sendable, Hashable {
	public var id: String
	public var name: String
	public var href: URL?
	public var uri: String
	public var albumType: String
	public var albumGroup: String?
	public var artists: [SpotifyArtist]
	public var images: [SpotifyImage]
	public var availableMarkets: [String]
	public var totalTracks: Int
	public var releaseDate: String?
	public var releaseDatePrecision: String?
	public var tracks: SpotifyPaging<SpotifyTrack>?

	public init(
		id: String,
		name: String,
		href: URL? = nil,
		uri: String = "",
		albumType: String = "album",
		albumGroup: String? = nil,
		artists: [SpotifyArtist] = [],
		images: [SpotifyImage] = [],
		availableMarkets: [String] = [],
		totalTracks: Int = 0,
		releaseDate: String? = nil,
		releaseDatePrecision: String? = nil,
		tracks: SpotifyPaging<SpotifyTrack>? = nil
	) {
		self.id = id
		self.name = name
		self.href = href
		self.uri = uri
		self.albumType = albumType
		self.albumGroup = albumGroup
		self.artists = artists
		self.images = images
		self.availableMarkets = availableMarkets
		self.totalTracks = totalTracks
		self.releaseDate = releaseDate
		self.releaseDatePrecision = releaseDatePrecision
		self.tracks = tracks
	}
}

public struct SpotifyTrack: Sendable, Hashable {
	public var id: String
	public var name: String
	public var href: URL?
	public var uri: String
	public var artists: [SpotifyArtist]
	public var album: SpotifyAlbum?
	public var durationMS: Int
	public var previewURL: URL?
	public var isExplicit: Bool?
	public var discNumber: Int?
	public var trackNumber: Int?
	public var isLocal: Bool?

	public init(
		id: String,
		name: String,
		href: URL? = nil,
		uri: String = "",
		artists: [SpotifyArtist] = [],
		album: SpotifyAlbum? = nil,
		durationMS: Int = 0,
		previewURL: URL? = nil,
		isExplicit: Bool? = nil,
		discNumber: Int? = nil,
		trackNumber: Int? = nil,
		isLocal: Bool? = nil
	) {
		self.id = id
		self.name = name
		self.href = href
		self.uri = uri
		self.artists = artists
		self.album = album
		self.durationMS = durationMS
		self.previewURL = previewURL
		self.isExplicit = isExplicit
		self.discNumber = discNumber
		self.trackNumber = trackNumber
		self.isLocal = isLocal
	}
}

public struct SpotifyPlaylistOwner: Sendable, Hashable {
	public var id: String
	public var displayName: String?
	public var href: URL?
	public var uri: String

	public init(id: String, displayName: String? = nil, href: URL? = nil, uri: String = "") {
		self.id = id
		self.displayName = displayName
		self.href = href
		self.uri = uri
	}
}

public struct SpotifyPlaylist: Sendable, Hashable {
	public var id: String
	public var name: String
	public var href: URL?
	public var uri: String
	public var description: String?
	public var owner: SpotifyPlaylistOwner?
	public var images: [SpotifyImage]
	public var totalTracks: Int?
	public var tracks: SpotifyPaging<SpotifyTrack>?

	public init(
		id: String,
		name: String,
		href: URL? = nil,
		uri: String = "",
		description: String? = nil,
		owner: SpotifyPlaylistOwner? = nil,
		images: [SpotifyImage] = [],
		totalTracks: Int? = nil,
		tracks: SpotifyPaging<SpotifyTrack>? = nil
	) {
		self.id = id
		self.name = name
		self.href = href
		self.uri = uri
		self.description = description
		self.owner = owner
		self.images = images
		self.totalTracks = totalTracks
		self.tracks = tracks
	}
}

public struct SpotifySearchResults: Sendable, Hashable {
	public var tracks: SpotifyPaging<SpotifyTrack>?
	public var artists: SpotifyPaging<SpotifyArtist>?
	public var albums: SpotifyPaging<SpotifyAlbum>?
	public var playlists: SpotifyPaging<SpotifyPlaylist>?

	public init(
		tracks: SpotifyPaging<SpotifyTrack>? = nil,
		artists: SpotifyPaging<SpotifyArtist>? = nil,
		albums: SpotifyPaging<SpotifyAlbum>? = nil,
		playlists: SpotifyPaging<SpotifyPlaylist>? = nil
	) {
		self.tracks = tracks
		self.artists = artists
		self.albums = albums
		self.playlists = playlists
	}
}