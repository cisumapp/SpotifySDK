import Foundation
import SpotifySDKCore

public actor SpotifyPathfinderClient {
    private let auth: SpotifyAuthService
    private let transport: any SpotifyTransport
    private let baseURL: URL

    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    public init(
        auth: SpotifyAuthService,
        transport: any SpotifyTransport = URLSessionSpotifyTransport()
    ) {
        self.auth = auth
        self.transport = transport
        self.baseURL = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!
    }

    // MARK: - Raw Query

    public func performQuery(
        operation: SpotifyPathfinderOperation,
        variables: [String: Any]
    ) async throws -> Data {
        let tokens = try await auth.currentSessionTokens()
        return try await performQuery(tokens: tokens, operation: operation, variables: variables)
    }

    private func performQuery(
        tokens: SpotifySessionTokens,
        operation: SpotifyPathfinderOperation,
        variables: [String: Any]
    ) async throws -> Data {
        let payload: [String: Any] = [
            "variables": variables,
            "operationName": operation.operationName,
            "extensions": [
                "persistedQuery": [
                    "version": 1,
                    "sha256Hash": operation.sha256Hash
                ]
            ]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        var headers: [String: String] = [
            "Authorization": "Bearer \(tokens.accessToken.value)",
            "App-Platform": "WebPlayer",
            "User-Agent": Self.defaultUserAgent,
            "Accept": "application/json",
            "Content-Type": "application/json;charset=UTF-8"
        ]

        // Ensure client-token is lowercase as per working Daagify implementation
        if let clientToken = tokens.clientToken?.value {
            headers["client-token"] = clientToken
        }

        let request = SpotifyHTTPRequest(
            url: baseURL,
            method: .post,
            headers: headers,
            body: body
        )

        Logger.log("Pathfinder: Sending query '\(operation.operationName)'")
        let (data, response) = try await transport.send(request.urlRequest())

        guard response.isSuccess else {
            let status = response.statusCode
            Logger.log("Pathfinder: Query '\(operation.operationName)' failed with status \(status)")
            if status == 401 {
                throw SpotifySDKError.transportFailed(
                    "Pathfinder query '\(operation.operationName)' returned HTTP 401. This indicates the Authorization token (Bearer...) was rejected."
                )
            } else {
                throw SpotifySDKError.transportFailed(
                    "Pathfinder query '\(operation.operationName)' returned HTTP \(status)."
                )
            }
        }

        Logger.log("Pathfinder: Query '\(operation.operationName)' succeeded (\(data.count) bytes)")
        return data
    }

    private func decodeResponse<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let rawData = String(data: data, encoding: .utf8) {
                print("🔴 [SpotifyPathfinder] Decoding failed for \(context). Raw JSON: \(rawData)")
            }
            throw error
        }
    }

    // MARK: - Typed Convenience Methods

    public func fetchPlaylistContents(
        uri: String,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> SpotifyPlaylist {
        let variables: [String: Any] = [
            "uri": uri,
            "offset": offset,
            "limit": limit,
            "includeEpisodeContentRatingsV2": false
        ]

        let data = try await performQuery(operation: SpotifyPathfinderOperation.fetchPlaylistContents, variables: variables)
        
        do {
            let response = try JSONDecoder().decode(PathfinderPlaylistResponse.self, from: data)
            return response.toDomain()
        } catch {
            if let rawData = String(data: data, encoding: .utf8) {
                print("🔴 [SpotifyPathfinder] Decoding failed for '\(uri)'. Raw JSON: \(rawData)")
            }
            throw error
        }
    }

    public func fetchAlbum(
        id: String,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> SpotifyAlbum {
        try await fetchAlbum(uri: spotifyPathfinderURI(kind: "album", value: id), offset: offset, limit: limit)
    }

    public func fetchAlbum(
        uri: String,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> SpotifyAlbum {
        let variables: [String: Any] = [
            "uri": uri,
            "locale": "",
            "offset": offset,
            "limit": limit
        ]

        let data = try await performQuery(operation: .getAlbum, variables: variables)
        let response = try decodeResponse(PathfinderAlbumResponse.self, from: data, context: "album '\(uri)'")

        guard let album = response.toDomain() else {
            throw SpotifySDKError.invalidResponse
        }

        return album
    }

    public func fetchArtist(
        id: String,
        locale: String = "",
        preReleaseV2: Bool = false
    ) async throws -> SpotifyArtist {
        try await fetchArtist(uri: spotifyPathfinderURI(kind: "artist", value: id), locale: locale, preReleaseV2: preReleaseV2)
    }

    public func fetchArtist(
        uri: String,
        locale: String = "",
        preReleaseV2: Bool = false
    ) async throws -> SpotifyArtist {
        let variables: [String: Any] = [
            "uri": uri,
            "locale": locale,
            "preReleaseV2": preReleaseV2
        ]

        let data = try await performQuery(operation: .getArtist, variables: variables)
        let response = try decodeResponse(PathfinderArtistResponse.self, from: data, context: "artist '\(uri)'")

        guard let artist = response.toDomain() else {
            throw SpotifySDKError.invalidResponse
        }

        return artist
    }

    public func fetchHome(
        timeZoneIdentifier: String = TimeZone.current.identifier,
        homeEndUserIntegration: String = "INTEGRATION_WEB_PLAYER",
        facet: String = "",
        sectionItemsLimit: Int = 10,
        includeEpisodeContentRatingsV2: Bool = false
    ) async throws -> SpotifyPathfinderDocument {
        let tokens = try await auth.currentSessionTokens()
        guard let webPlayerCookie = tokens.spotifyWebPlayerCookie, !webPlayerCookie.isEmpty else {
            throw SpotifySDKError.missingConfiguration("Home queries require the Spotify web player cookie `sp_t`.")
        }

        let variables: [String: Any] = [
            "homeEndUserIntegration": homeEndUserIntegration,
            "timeZone": timeZoneIdentifier,
            "sp_t": webPlayerCookie,
            "facet": facet,
            "sectionItemsLimit": sectionItemsLimit,
            "includeEpisodeContentRatingsV2": includeEpisodeContentRatingsV2
        ]

        let data = try await performQuery(tokens: tokens, operation: .home, variables: variables)
        let response = try decodeResponse(PathfinderHomeResponse.self, from: data, context: "home")

        guard let document = response.data else {
            throw SpotifySDKError.invalidResponse
        }

        return SpotifyPathfinderDocument(data: document)
    }

    public func fetchLibraryV3(
        filters: [String] = ["Playlists"],
        order: String? = nil,
        textFilter: String = "",
        features: [String] = ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "PRERELEASES_V2", "EVENTS"],
        limit: Int = 50,
        offset: Int = 0,
        flatten: Bool = false,
        expandedFolders: [String] = [],
        folderUri: String? = nil,
        includeFoldersWhenFlattening: Bool = true
    ) async throws -> SpotifyPathfinderDocument {
        let variables: [String: Any] = [
            "filters": filters,
            "order": order ?? NSNull(),
            "textFilter": textFilter,
            "features": features,
            "limit": limit,
            "offset": offset,
            "flatten": flatten,
            "expandedFolders": expandedFolders,
            "folderUri": folderUri ?? NSNull(),
            "includeFoldersWhenFlattening": includeFoldersWhenFlattening
        ]

        let data = try await performQuery(operation: .libraryV3, variables: variables)
        let response = try decodeResponse(PathfinderLibraryResponse.self, from: data, context: "libraryV3")

        guard let document = response.data else {
            throw SpotifySDKError.invalidResponse
        }

        return SpotifyPathfinderDocument(data: document)
    }

    public func fetchLibraryV3Page(
        filters: [String] = ["Playlists"],
        order: String? = nil,
        textFilter: String = "",
        features: [String] = ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "PRERELEASES_V2", "EVENTS"],
        limit: Int = 50,
        offset: Int = 0,
        flatten: Bool = false,
        expandedFolders: [String] = [],
        folderUri: String? = nil,
        includeFoldersWhenFlattening: Bool = true
    ) async throws -> SpotifyLibraryPage {
        let variables: [String: Any] = [
            "filters": filters,
            "order": order ?? NSNull(),
            "textFilter": textFilter,
            "features": features,
            "limit": limit,
            "offset": offset,
            "flatten": flatten,
            "expandedFolders": expandedFolders,
            "folderUri": folderUri ?? NSNull(),
            "includeFoldersWhenFlattening": includeFoldersWhenFlattening
        ]

        let data = try await performQuery(operation: .libraryV3, variables: variables)
        let response = try decodeResponse(SpotifyLibraryV3Response.self, from: data, context: "libraryV3")
        return response.toDomain()
    }

    public func fetchLibraryTracks(offset: Int = 0, limit: Int = 50) async throws -> SpotifyLikedSongsPage {
        let variables: [String: Any] = [
            "offset": offset,
            "limit": limit
        ]

        let data = try await performQuery(operation: .fetchLibraryTracks, variables: variables)
        let response = try decodeResponse(SpotifyUserLibraryTracksResponse.self, from: data, context: "fetchLibraryTracks")
        return response.toDomain()
    }

    private func spotifyPathfinderURI(kind: String, value: String) -> String {
        let prefix = "spotify:\(kind):"
        return value.hasPrefix(prefix) ? value : "\(prefix)\(value)"
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
        let variables: [String: Any] = [
            "searchTerm": searchText,
            "offset": offset,
            "limit": limit,
            "numberOfTopResults": numberOfTopResults,
            "includeAudiobooks": includeAudiobooks,
            "includeArtistHasConcertsField": includeArtistHasConcertsField,
            "includePreReleases": includePreReleases,
            "includeAuthors": includeAuthors,
            "includeEpisodeContentRatingsV2": includeEpisodeContentRatingsV2
        ]

        let data = try await self.performQuery(operation: SpotifyPathfinderOperation.search, variables: variables)

        do {
            let response = try JSONDecoder().decode(PathfinderSearchResponse.self, from: data)
            return response.toDomain()
        } catch {
            if let rawData = String(data: data, encoding: .utf8) {
                print("🔴 [SpotifyPathfinder] Decoding failed for search '\(searchText)'. Raw JSON: \(rawData)")
            }
            throw error
        }
    }

    public func fetchTrack(uri: String) async throws -> SpotifyTrack {
        let data = try await performQuery(operation: SpotifyPathfinderOperation.getTrack, variables: ["uri": uri])

        do {
            let response = try JSONDecoder().decode(PathfinderTrackResponse.self, from: data)
            guard let track = response.toDomain() else {
                throw SpotifySDKError.invalidResponse
            }
            return track
        } catch {
            if let rawData = String(data: data, encoding: .utf8) {
                print("🔴 [SpotifyPathfinder] Decoding failed for track '\(uri)'. Raw JSON: \(rawData)")
            }
            throw error
        }
    }
}
