import Foundation
import SpotifySDKCore

struct PathfinderSearchResponse: Decodable {
	let data: PathfinderSearchData?

	func toDomain() -> SpotifySearchResults {
		data?.searchV2?.toDomain() ?? SpotifySearchResults()
	}
}

struct PathfinderSearchData: Decodable {
	let searchV2: PathfinderSearchV2?
}

struct PathfinderSearchV2: Decodable {
	let tracksV2: PathfinderSearchTrackPage?
	let artists: PathfinderSearchArtistPage?
	let albumsV2: PathfinderSearchAlbumPage?
	let playlists: PathfinderSearchPlaylistPage?

	func toDomain() -> SpotifySearchResults {
		SpotifySearchResults(
			tracks: tracksV2?.toDomain(),
			artists: artists?.toDomain(),
			albums: albumsV2?.toDomain(),
			playlists: playlists?.toDomain()
		)
	}
}

struct PathfinderSearchTrackPage: Decodable {
	let items: [PathfinderSearchHit<PathfinderSearchTrackWrapper>]
	let totalCount: Int?

	func toDomain() -> SpotifyPaging<SpotifyTrack> {
		SpotifyPaging(
			items: items.compactMap { $0.item?.toDomain() },
			total: totalCount
		)
	}
}

struct PathfinderSearchArtistPage: Decodable {
	let items: [PathfinderSearchArtistWrapper]
	let totalCount: Int?

	func toDomain() -> SpotifyPaging<SpotifyArtist> {
		SpotifyPaging(
			items: items.compactMap { $0.toDomain() },
			total: totalCount
		)
	}
}

struct PathfinderSearchAlbumPage: Decodable {
	let items: [PathfinderSearchAlbumWrapper]
	let totalCount: Int?

	func toDomain() -> SpotifyPaging<SpotifyAlbum> {
		SpotifyPaging(
			items: items.compactMap { $0.toDomain() },
			total: totalCount
		)
	}
}

struct PathfinderSearchPlaylistPage: Decodable {
	let items: [PathfinderSearchPlaylistWrapper]
	let totalCount: Int?

	func toDomain() -> SpotifyPaging<SpotifyPlaylist> {
		SpotifyPaging(
			items: items.compactMap { $0.toDomain() },
			total: totalCount
		)
	}
}

struct PathfinderSearchHit<Item: Decodable>: Decodable {
	let item: Item?
	let matchedFields: [String]?
}

struct PathfinderSearchTrackWrapper: Decodable {
	let data: PathfinderSearchTrackData?

	func toDomain() -> SpotifyTrack? {
		data?.toDomain()
	}
}

struct PathfinderSearchTrackData: Decodable {
	let typename: String?
	let id: String?
	let name: String?
	let uri: String?
	let duration: PathfinderDuration?
	let contentRating: PathfinderContentRating?
	let trackNumber: Int?
	let trackMediaType: String?
	let artists: PathfinderTrackArtistCollection?
	let albumOfTrack: PathfinderTrackAlbumOfTrack?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case id
		case name
		case uri
		case duration
		case contentRating
		case trackNumber
		case trackMediaType
		case artists
		case albumOfTrack
	}

	func toDomain() -> SpotifyTrack {
		let artistItems = artists?.items.compactMap { $0.toDomain() } ?? []

		return SpotifyTrack(
			id: id ?? spotifySearchPathfinderExtractID(from: uri ?? ""),
			name: name ?? "Unknown Track",
			href: nil,
			uri: uri ?? "",
			artists: artistItems,
			album: albumOfTrack?.toDomain(artists: artistItems),
			durationMS: duration?.totalMilliseconds ?? 0,
			isExplicit: contentRating.map { $0.label == "EXPLICIT" },
			trackNumber: trackNumber,
			isLocal: trackMediaType == "AUDIO" ? false : nil
		)
	}
}

struct PathfinderSearchArtistWrapper: Decodable {
	let data: PathfinderSearchArtistData?

	func toDomain() -> SpotifyArtist? {
		data?.toDomain()
	}
}

struct PathfinderSearchArtistData: Decodable {
	let typename: String?
	let id: String?
	let uri: String?
	let profile: PathfinderArtistProfile?
	let visuals: PathfinderTrackArtistVisuals?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case id
		case uri
		case profile
		case visuals
	}

	func toDomain() -> SpotifyArtist {
		SpotifyArtist(
			id: id ?? spotifySearchPathfinderExtractID(from: uri ?? ""),
			name: profile?.name ?? "Unknown Artist",
			href: nil,
			uri: uri ?? "",
			images: visuals?.avatarImage?.sources.compactMap { $0.toSearchDomain() } ?? []
		)
	}
}

struct PathfinderSearchAlbumWrapper: Decodable {
	let data: PathfinderSearchAlbumData?

	func toDomain() -> SpotifyAlbum? {
		data?.toDomain()
	}
}

struct PathfinderSearchAlbumData: Decodable {
	let typename: String?
	let id: String?
	let name: String?
	let uri: String?
	let type: String?
	let date: PathfinderSearchAlbumDate?
	let artists: PathfinderTrackArtistCollection?
	let coverArt: PathfinderTrackCoverArt?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case id
		case name
		case uri
		case type
		case date
		case artists
		case coverArt
	}

	func toDomain() -> SpotifyAlbum {
		SpotifyAlbum(
			id: id ?? spotifySearchPathfinderExtractID(from: uri ?? ""),
			name: name ?? "Unknown Album",
			href: nil,
			uri: uri ?? "",
			albumType: type?.lowercased() ?? "album",
			artists: artists?.items.compactMap { $0.toDomain() } ?? [],
			images: coverArt?.sources.compactMap { $0.toSearchDomain() } ?? [],
			availableMarkets: [],
			totalTracks: 0,
			releaseDate: date?.year.map(String.init),
			releaseDatePrecision: date?.precision?.lowercased(),
			tracks: nil
		)
	}
}

struct PathfinderSearchAlbumDate: Decodable {
	let year: Int?
	let precision: String?
}

struct PathfinderSearchPlaylistWrapper: Decodable {
	let data: PathfinderSearchPlaylistData?

	func toDomain() -> SpotifyPlaylist? {
		data?.toDomain()
	}
}

struct PathfinderSearchPlaylistData: Decodable {
	let typename: String?
	let id: String?
	let name: String?
	let uri: String?
	let description: String?
	let ownerV2: PathfinderOwnerV2?
	let images: PathfinderImageList?
	let tracks: PathfinderSearchPlaylistTracks?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case id
		case name
		case uri
		case description
		case ownerV2
		case images
		case tracks
	}

	func toDomain() -> SpotifyPlaylist {
		SpotifyPlaylist(
			id: id ?? spotifySearchPathfinderExtractID(from: uri ?? ""),
			name: name ?? "Unknown Playlist",
			href: nil,
			uri: uri ?? "",
			description: description,
			owner: ownerV2?.toDomain(),
			images: images?.items.compactMap { $0.toDomain() } ?? [],
			totalTracks: tracks?.totalCount,
			tracks: nil
		)
	}
}

struct PathfinderSearchPlaylistTracks: Decodable {
	let totalCount: Int?
}

struct PathfinderSearchSuggestionsResponse: Decodable {
	let data: PathfinderSearchSuggestionsData?

	func toDomain() -> [SpotifySearchSuggestion] {
		data?.searchV2?.topResultsV2?.itemsV2.compactMap { $0.toDomain() } ?? []
	}
}

struct PathfinderSearchSuggestionsData: Decodable {
	let searchV2: PathfinderSearchSuggestionsV2?
}

struct PathfinderSearchSuggestionsV2: Decodable {
	let topResultsV2: PathfinderSearchSuggestionsTopResults?
}

struct PathfinderSearchSuggestionsTopResults: Decodable {
	let itemsV2: [PathfinderSearchSuggestionsHit]
}

struct PathfinderSearchSuggestionsHit: Decodable {
	let item: PathfinderSearchSuggestionsItem?

	func toDomain() -> SpotifySearchSuggestion? {
		item?.toDomain()
	}
}

struct PathfinderSearchSuggestionsItem: Decodable {
	let typename: String?
	let data: PathfinderSearchSuggestionsItemData?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case data
	}

	func toDomain() -> SpotifySearchSuggestion? {
		guard let data else { return nil }
		guard let uri = data.uri else { return nil }
		let title = data.text ?? data.profile?.name ?? data.name ?? uri

		return SpotifySearchSuggestion(
			title: title,
			uri: uri,
			typeName: typename ?? data.typename
		)
	}
}

struct PathfinderSearchSuggestionsItemData: Decodable {
	let typename: String?
	let text: String?
	let uri: String?
	let profile: PathfinderArtistProfile?
	let name: String?

	private enum CodingKeys: String, CodingKey {
		case typename = "__typename"
		case text
		case uri
		case profile
		case name
	}

	var title: String {
		if let text {
			return text
		}

		if let profileName = profile?.name {
			return profileName
		}

		if let name {
			return name
		}

		if let uri {
			return uri
		}

		return "Unknown"
	}
}

private func spotifySearchPathfinderExtractID(from uri: String) -> String {
	uri.split(separator: ":").last.map(String.init) ?? uri
}

private extension PathfinderImageSource {
	func toSearchDomain() -> SpotifyImage? {
		guard let url, let imageURL = URL(string: url) else {
			return nil
		}

		return SpotifyImage(url: imageURL, width: width, height: height)
	}
}
