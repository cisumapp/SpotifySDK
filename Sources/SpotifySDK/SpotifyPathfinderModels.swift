import Foundation
import SpotifySDKCore

// MARK: - Playlist Response

struct PathfinderPlaylistResponse: Decodable {
    let data: PathfinderPlaylistData?

    func toDomain() -> SpotifyPlaylist {
        guard let playlist = data?.playlistV2 else {
            Logger.log("PathfinderPlaylistResponse: No playlistV2 data found in response.")
            return SpotifyPlaylist(id: "", name: "Spotify Playlist")
        }

        let items = playlist.content?.items.compactMap { $0.toDomainTrack() } ?? []
        let paging = SpotifyPaging<SpotifyTrack>(
            items: items,
            limit: playlist.content?.limit,
            offset: playlist.content?.offset,
            total: playlist.content?.totalCount
        )

        let resolvedName = normalizedPlaylistName(playlist.name)
        Logger.log("PathfinderPlaylistResponse: Resolved name '\(resolvedName)' from raw '\(playlist.name ?? "nil")' for URI \(playlist.uri ?? "unknown")")

        return SpotifyPlaylist(
            id: spotifyPathfinderExtractID(from: playlist.uri ?? ""),
            name: resolvedName,
            uri: playlist.uri ?? "",
            description: playlist.description,
            owner: playlist.ownerV2?.toDomain(),
            images: playlist.images?.items.compactMap { $0.toDomain() } ?? [],
            totalTracks: playlist.content?.totalCount,
            tracks: paging
        )
    }
}

struct PathfinderPlaylistData: Decodable {
    let playlistV2: PathfinderPlaylistV2?
}

struct PathfinderPlaylistV2: Decodable {
    let uri: String?
    let name: String?
    let description: String?
    let ownerV2: PathfinderOwnerV2?
    let images: PathfinderImageList?
    let content: PathfinderPlaylistContent?
}

struct PathfinderPlaylistContent: Decodable {
    let items: [PathfinderPlaylistItem]
    let totalCount: Int?
    let limit: Int?
    let offset: Int?
}

struct PathfinderPlaylistItem: Decodable {
    let addedAt: PathfinderTimestamp?
    let itemV2: PathfinderTrackWrapper?
    let uid: String?

    func toDomainTrack() -> SpotifyTrack? {
        guard let trackData = itemV2?.data, trackData.isPlayableContent else {
            return nil
        }

        return trackData.toDomain()
    }
}

struct PathfinderTimestamp: Decodable {
    let isoString: String?
}

struct PathfinderTrackWrapper: Decodable {
    let data: PathfinderTrackData?

    private enum CodingKeys: String, CodingKey {
        case data
    }
}

struct PathfinderTrackData: Decodable {
    let typename: String?
    let id: String?
    let name: String?
    let uri: String?
    let duration: PathfinderDuration?
    let trackDuration: PathfinderDuration?
    let discNumber: Int?
    let trackNumber: Int?
    let playcount: String?
    let contentRating: PathfinderContentRating?
    let artists: PathfinderArtistList?
    let albumOfTrack: PathfinderAlbumOfTrack?
    let mediaType: String?
    let trackMediaType: String?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, name, uri, duration, trackDuration, discNumber, trackNumber
        case playcount, contentRating, artists, albumOfTrack, mediaType, trackMediaType
    }

    var isPlayableContent: Bool {
        guard let typename else { return true }
        return typename == "Track" || typename == "Episode"
    }

    func toDomain(fallbackURI: String? = nil) -> SpotifyTrack {
        let finalURI = uri ?? fallbackURI ?? ""
        let artists = artists?.items.compactMap { $0.toDomain() } ?? []
        let album = albumOfTrack?.toDomain(artists: artists)
        let resolvedID = id ?? spotifyPathfinderExtractID(from: finalURI)

        if resolvedID.isEmpty {
            Logger.log("PathfinderTrackData: WARNING - Resolved ID is empty for track '\(name ?? "unknown")' (URI: \(finalURI), data.uri: \(uri ?? "nil"), fallback: \(fallbackURI ?? "nil"))")
        }

        return SpotifyTrack(
            id: resolvedID,
            name: name ?? "Unknown Track",
            uri: finalURI,
            artists: artists,
            album: album,
            durationMS: duration?.totalMilliseconds ?? trackDuration?.totalMilliseconds ?? 0,
            isExplicit: contentRating.map { $0.label == "EXPLICIT" },
            discNumber: discNumber,
            trackNumber: trackNumber,
            isLocal: (mediaType ?? trackMediaType) == "AUDIO" ? false : nil
        )
    }
}

struct PathfinderDuration: Decodable {
    let totalMilliseconds: Int?
}

struct PathfinderContentRating: Decodable {
    let label: String?
}

struct PathfinderArtistList: Decodable {
    let items: [PathfinderArtistItem]
}

struct PathfinderArtistItem: Decodable {
    let uri: String?
    let profile: PathfinderArtistProfile?

    func toDomain() -> SpotifyArtist {
        SpotifyArtist(
            id: spotifyPathfinderExtractID(from: uri ?? ""),
            name: profile?.name ?? "Unknown Artist",
            href: nil,
            uri: uri ?? ""
        )
    }
}

struct PathfinderArtistProfile: Decodable {
    let name: String?
}

struct PathfinderAlbumOfTrack: Decodable {
    let name: String?
    let uri: String?
    let artists: PathfinderAlbumArtistList?
    let coverArt: PathfinderCoverArt?

    func toDomain(artists: [SpotifyArtist]) -> SpotifyAlbum {
        let albumArtists = artists.isEmpty ? (self.artists?.items.compactMap { $0.toDomain() } ?? []) : artists
        let albumImages = coverArt?.sources.compactMap { $0.toDomain() } ?? []

        return SpotifyAlbum(
            id: spotifyPathfinderExtractID(from: uri ?? ""),
            name: name ?? "Unknown Album",
            href: nil,
            uri: uri ?? "",
            albumType: "album",
            artists: albumArtists,
            images: albumImages,
            totalTracks: 0,
            tracks: nil
        )
    }
}

struct PathfinderAlbumArtistList: Decodable {
    let items: [PathfinderAlbumArtistItem]
}

struct PathfinderAlbumArtistItem: Decodable {
    let uri: String?
    let profile: PathfinderArtistProfile?

    func toDomain() -> SpotifyArtist {
        SpotifyArtist(
            id: spotifyPathfinderExtractID(from: uri ?? ""),
            name: profile?.name ?? "Unknown Artist",
            href: nil,
            uri: uri ?? ""
        )
    }
}

struct PathfinderCoverArt: Decodable {
    let sources: [PathfinderImageSource]
}

struct PathfinderImageSource: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

// MARK: - Owner & Images

struct PathfinderOwnerV2: Decodable {
    let data: PathfinderOwnerData?

    func toDomain() -> SpotifyPlaylistOwner? {
        guard let data = data else { return nil }
        let id = spotifyPathfinderExtractID(from: data.uri ?? "")
        return SpotifyPlaylistOwner(
            id: id,
            displayName: data.name ?? data.username,
            uri: data.uri ?? ""
        )
    }
}

struct PathfinderOwnerData: Decodable {
    let name: String?
    let uri: String?
    let username: String?
}

struct PathfinderImageList: Decodable {
    let items: [PathfinderImageItem]
}

struct PathfinderImageItem: Decodable {
    let sources: [PathfinderImageSource]

    func toDomain() -> SpotifyImage? {
        guard let source = sources.first,
              let urlString = source.url,
              let url = URL(string: urlString) else {
            return nil
        }

        return SpotifyImage(url: url, width: source.width, height: source.height)
    }
}

// MARK: - Track Response

struct PathfinderTrackResponse: Decodable {
    let data: PathfinderTrackResponseData?

    func toDomain() -> SpotifyTrack? {
        data?.trackUnion?.toDomain()
    }
}

struct PathfinderTrackResponseData: Decodable {
    let trackUnion: PathfinderTrackUnion?
}

struct PathfinderTrackUnion: Decodable {
    let typename: String?
    let id: String?
    let name: String?
    let mediaType: String?
    let uri: String?
    let duration: PathfinderDuration?
    let contentRating: PathfinderContentRating?
    let trackNumber: Int?
    let previews: PathfinderTrackPreviews?
    let albumOfTrack: PathfinderTrackAlbumOfTrack?
    let firstArtist: PathfinderTrackArtistCollection?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id
        case name
        case mediaType
        case uri
        case duration
        case contentRating
        case trackNumber
        case previews
        case albumOfTrack
        case firstArtist
    }

    func toDomain() -> SpotifyTrack {
        let artists = firstArtist?.items.compactMap { $0.toDomain() } ?? []
        let album = albumOfTrack?.toDomain(artists: artists)
        let previewURL = previews?.audioPreviews?.items.first?.url.flatMap { URL(string: $0) }

        return SpotifyTrack(
            id: id ?? spotifyPathfinderExtractID(from: uri ?? ""),
            name: name ?? "Unknown Track",
            uri: uri ?? "",
            artists: artists,
            album: album,
            durationMS: duration?.totalMilliseconds ?? 0,
            previewURL: previewURL,
            isExplicit: contentRating.map { $0.label == "EXPLICIT" },
            discNumber: nil,
            trackNumber: trackNumber,
            isLocal: mediaType == "AUDIO" ? false : nil
        )
    }
}

struct PathfinderTrackPreviews: Decodable {
    let audioPreviews: PathfinderTrackAudioPreviewCollection?
}

struct PathfinderTrackAudioPreviewCollection: Decodable {
    let items: [PathfinderTrackAudioPreviewItem]
}

struct PathfinderTrackAudioPreviewItem: Decodable {
    let url: String?
}

struct PathfinderTrackAlbumOfTrack: Decodable {
    let id: String?
    let date: PathfinderTrackReleaseDate?
    let name: String?
    let tracks: PathfinderTrackAlbumTrackCollection?
    let type: String?
    let uri: String?
    let coverArt: PathfinderTrackCoverArt?

    func toDomain(artists: [SpotifyArtist]) -> SpotifyAlbum {
        SpotifyAlbum(
            id: id ?? spotifyPathfinderExtractID(from: uri ?? ""),
            name: name ?? "Unknown Album",
            href: nil,
            uri: uri ?? "",
            albumType: type?.lowercased() ?? "album",
            artists: artists,
            images: coverArt?.sources.compactMap { $0.toDomain() } ?? [],
            totalTracks: tracks?.totalCount ?? 0,
            releaseDate: date?.isoString,
            releaseDatePrecision: date?.precision?.lowercased(),
            tracks: nil
        )
    }
}

struct PathfinderTrackReleaseDate: Decodable {
    let isoString: String?
    let precision: String?
    let year: Int?
}

struct PathfinderTrackAlbumTrackCollection: Decodable {
    let items: [PathfinderTrackAlbumTrackItem]?
    let totalCount: Int?
}

struct PathfinderTrackAlbumTrackItem: Decodable {
    let track: PathfinderTrackAlbumTrackReference?
}

struct PathfinderTrackAlbumTrackReference: Decodable {
    let trackNumber: Int?
    let uri: String?
}

struct PathfinderTrackCoverArt: Decodable {
    let sources: [PathfinderImageSource]
}

struct PathfinderTrackArtistCollection: Decodable {
    let items: [PathfinderTrackArtistItem]
}

struct PathfinderTrackArtistItem: Decodable {
    let id: String?
    let uri: String?
    let profile: PathfinderArtistProfile?
    let visuals: PathfinderTrackArtistVisuals?

    func toDomain() -> SpotifyArtist {
        SpotifyArtist(
            id: id ?? spotifyPathfinderExtractID(from: uri ?? ""),
            name: profile?.name ?? "Unknown Artist",
            href: nil,
            uri: uri ?? "spotify:artist:\(id ?? "")",
            images: visuals?.avatarImage?.sources.compactMap { $0.toDomain() } ?? []
        )
    }
}

struct PathfinderTrackArtistVisuals: Decodable {
    let avatarImage: PathfinderTrackAvatarImage?
}

struct PathfinderTrackAvatarImage: Decodable {
    let sources: [PathfinderImageSource]
}

private func normalizedPlaylistName(_ name: String?) -> String {
    return name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func spotifyPathfinderExtractID(from uri: String) -> String {
    uri.split(separator: ":").last.map(String.init) ?? uri
}

extension PathfinderImageSource {
    func toDomain() -> SpotifyImage? {
        guard let url, let imageURL = URL(string: url) else {
            return nil
        }

        return SpotifyImage(url: imageURL, width: width, height: height)
    }
}