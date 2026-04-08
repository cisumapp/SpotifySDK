import Foundation
import SpotifySDKCore

public enum SpotifyJSONValue: Sendable, Hashable, Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SpotifyJSONValue])
    case object([String: SpotifyJSONValue])

    public init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer() {
            if singleValueContainer.decodeNil() {
                self = .null
                return
            }

            if let bool = try? singleValueContainer.decode(Bool.self) {
                self = .bool(bool)
                return
            }

            if let int = try? singleValueContainer.decode(Int.self) {
                self = .int(int)
                return
            }

            if let double = try? singleValueContainer.decode(Double.self) {
                self = .double(double)
                return
            }

            if let string = try? singleValueContainer.decode(String.self) {
                self = .string(string)
                return
            }
        }

        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var values: [SpotifyJSONValue] = []
            while !unkeyedContainer.isAtEnd {
                values.append(try unkeyedContainer.decode(SpotifyJSONValue.self))
            }
            self = .array(values)
            return
        }

        let keyedContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var object: [String: SpotifyJSONValue] = [:]
        object.reserveCapacity(keyedContainer.allKeys.count)
        for key in keyedContainer.allKeys {
            object[key.stringValue] = try keyedContainer.decode(SpotifyJSONValue.self, forKey: key)
        }
        self = .object(object)
    }

    public var objectValue: [String: SpotifyJSONValue]? {
        guard case let .object(object) = self else { return nil }
        return object
    }

    public var arrayValue: [SpotifyJSONValue]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}

public struct SpotifyPathfinderDocument: Sendable, Hashable, Decodable {
    public let data: SpotifyJSONValue?

    public init(data: SpotifyJSONValue? = nil) {
        self.data = data
    }
}

struct PathfinderAlbumResponse: Decodable {
    let data: PathfinderAlbumResponseData?

    func toDomain() -> SpotifyAlbum? {
        data?.albumUnion?.toDomain()
    }
}

struct PathfinderAlbumResponseData: Decodable {
    let albumUnion: PathfinderAlbumUnion?
}

struct PathfinderAlbumUnion: Decodable {
    let typename: String?
    let id: String?
    let name: String?
    let uri: String?
    let type: String?
    let albumType: String?
    let date: PathfinderAlbumDate?
    let artists: PathfinderTrackArtistCollection?
    let coverArt: PathfinderTrackCoverArt?
    let tracksV2: PathfinderAlbumTrackPage?
    let availableMarkets: [String]?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id
        case name
        case uri
        case type
        case albumType
        case date
        case artists
        case coverArt
        case tracksV2
        case availableMarkets
    }

    func toDomain() -> SpotifyAlbum {
        let albumArtists = artists?.items.compactMap { $0.toDomain() } ?? []
        let albumImages = coverArt?.sources.compactMap { $0.toDomain() } ?? []
        let trackItems = tracksV2?.items.compactMap { $0.toDomainTrack() } ?? []

        return SpotifyAlbum(
            id: id ?? spotifyPathfinderExtractID(from: uri ?? ""),
            name: name ?? "Unknown Album",
            uri: uri ?? "",
            albumType: (albumType ?? type ?? "album").lowercased(),
            artists: albumArtists,
            images: albumImages,
            availableMarkets: availableMarkets ?? [],
            totalTracks: tracksV2?.totalCount ?? trackItems.count,
            releaseDate: date?.isoString ?? date?.year.map(String.init),
            releaseDatePrecision: date?.precision?.lowercased(),
            tracks: SpotifyPaging(
                items: trackItems,
                limit: tracksV2?.limit,
                offset: tracksV2?.offset,
                total: tracksV2?.totalCount
            )
        )
    }
}

struct PathfinderAlbumDate: Decodable {
    let isoString: String?
    let year: Int?
    let precision: String?
}

struct PathfinderAlbumTrackPage: Decodable {
    let items: [PathfinderAlbumTrackEntry]
    let totalCount: Int?
    let limit: Int?
    let offset: Int?
}

struct PathfinderAlbumTrackEntry: Decodable {
    let data: PathfinderTrackData?
    let item: PathfinderTrackWrapper?
    let itemV2: PathfinderTrackWrapper?

    func toDomainTrack() -> SpotifyTrack? {
        if let data, data.isPlayableContent {
            return data.toDomain()
        }

        if let item, let trackData = item.data, trackData.isPlayableContent {
            return trackData.toDomain()
        }

        if let itemV2, let trackData = itemV2.data, trackData.isPlayableContent {
            return trackData.toDomain()
        }

        return nil
    }
}

struct PathfinderArtistResponse: Decodable {
    let data: PathfinderArtistResponseData?

    func toDomain() -> SpotifyArtist? {
        data?.artistUnion?.toDomain()
    }
}

struct PathfinderArtistResponseData: Decodable {
    let artistUnion: PathfinderArtistUnion?
}

struct PathfinderArtistUnion: Decodable {
    let typename: String?
    let id: String?
    let name: String?
    let uri: String?
    let profile: PathfinderArtistProfile?
    let visuals: PathfinderTrackArtistVisuals?
    let genres: [String]?
    let popularity: Int?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id
        case name
        case uri
        case profile
        case visuals
        case genres
        case popularity
    }

    func toDomain() -> SpotifyArtist {
        SpotifyArtist(
            id: id ?? spotifyPathfinderExtractID(from: uri ?? ""),
            name: profile?.name ?? name ?? "Unknown Artist",
            uri: uri ?? "",
            images: visuals?.avatarImage?.sources.compactMap { $0.toDomain() } ?? [],
            genres: genres ?? [],
            popularity: popularity
        )
    }
}

struct PathfinderHomeResponse: Decodable {
    let data: SpotifyJSONValue?
}

struct PathfinderLibraryResponse: Decodable {
    let data: SpotifyJSONValue?
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func spotifyPathfinderExtractID(from uri: String) -> String {
    uri.split(separator: ":").last.map(String.init) ?? uri
}