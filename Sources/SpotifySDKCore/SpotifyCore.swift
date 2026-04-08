import Foundation

public enum SpotifyClientMode: String, Sendable, Hashable {
    case publicWebPlayer
    case privateWebPlayer
}

public struct SpotifyAccessToken: Sendable, Hashable {
    public var value: String
    public var tokenType: String
    public var expiresAt: Date

    public init(
        value: String,
        tokenType: String = "Bearer",
        expiresAt: Date
    ) {
        self.value = value
        self.tokenType = tokenType
        self.expiresAt = expiresAt
    }

    public var authorizationHeaderValue: String {
        "\(tokenType) \(value)"
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

public struct SpotifyClientToken: Sendable, Hashable {
    public var value: String
    public var expiresAt: Date?

    public init(value: String, expiresAt: Date? = nil) {
        self.value = value
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else {
            return false
        }
        return Date() >= expiresAt
    }
}

public struct SpotifySessionTokens: Sendable, Hashable {
    public var accessToken: SpotifyAccessToken
    public var clientToken: SpotifyClientToken?
    public var refreshToken: String?
    public var scope: Set<String>
    public var clientID: String?
    public var spotifyWebPlayerCookie: String?
    public var isAnonymous: Bool

    public init(
        accessToken: SpotifyAccessToken,
        clientToken: SpotifyClientToken? = nil,
        refreshToken: String? = nil,
        scope: Set<String> = [],
        clientID: String? = nil,
        spotifyWebPlayerCookie: String? = nil,
        isAnonymous: Bool = true
    ) {
        self.accessToken = accessToken
        self.clientToken = clientToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.clientID = clientID
        self.spotifyWebPlayerCookie = spotifyWebPlayerCookie
        self.isAnonymous = isAnonymous
    }

    public var authorizationHeaderValue: String {
        accessToken.authorizationHeaderValue
    }

    public var isExpired: Bool {
        accessToken.isExpired || (clientToken?.isExpired ?? false)
    }
}

public struct SpotifyTOTPCode: Sendable, Hashable {
    public var value: String
    public var version: Int

    public init(value: String, version: Int) {
        self.value = value
        self.version = version
    }
}

public protocol SpotifyTOTPSource: Sendable {
    func currentCode(at date: Date) async throws -> SpotifyTOTPCode
}

public struct SpotifyPathfinderOperation: Sendable, Hashable {
    public var operationName: String
    public var sha256Hash: String

    public init(operationName: String, sha256Hash: String) {
        self.operationName = operationName
        self.sha256Hash = sha256Hash
    }
}

public extension SpotifyPathfinderOperation {
    static let home = SpotifyPathfinderOperation(
        operationName: "home",
        sha256Hash: "23e37f2e58d82d567f27080101d36609009d8c3676457b1086cb0acc55b72a5d"
    )

    static let libraryV3 = SpotifyPathfinderOperation(
        operationName: "libraryV3",
        sha256Hash: "973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3"
    )

    static let fetchLibraryTracks = SpotifyPathfinderOperation(
        operationName: "fetchLibraryTracks",
        sha256Hash: "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240"
    )

    static let profileAttributes = SpotifyPathfinderOperation(
        operationName: "profileAttributes",
        sha256Hash: "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced"
    )

    static let search = SpotifyPathfinderOperation(
        operationName: "searchDesktop",
        sha256Hash: "8929d7a459f78787b6f0d557f14261faa4d5d8f6ca171cff5bb491ee239caa83"
    )

    static let searchSuggestionsQuery = SpotifyPathfinderOperation(
        operationName: "searchSuggestions",
        sha256Hash: "9fe3ad78e43a1684b3a9fabc741c5928928d4d30d7d8fd7fd193c7ebb4a544f4"
    )

    static let getTrack = SpotifyPathfinderOperation(
        operationName: "getTrack",
        sha256Hash: "612585ae06ba435ad26369870deaae23b5c8800a256cd8a57e08eddc25a37294"
    )

    static let getAlbum = SpotifyPathfinderOperation(
        operationName: "getAlbum",
        sha256Hash: "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10"
    )

    static let getArtist = SpotifyPathfinderOperation(
        operationName: "queryArtistOverview",
        sha256Hash: "7f86ff63e38c24973a2842b672abe44c910c1973978dc8a4a0cb648edef34527"
    )

    static let fetchPlaylistContents = SpotifyPathfinderOperation(
        operationName: "fetchPlaylistContents",
        sha256Hash: "32b05e92e438438408674f95d0fdad8082865dc32acd55bd97f5113b8579092b"
    )
}

public enum SpotifySDKError: Error, LocalizedError, Sendable {
    case missingConfiguration(String)
    case invalidResponse
    case unauthorized(String)
    case decodingFailed(String)
    case transportFailed(String)
    case tokenExpired
    case unsupportedMode(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized(let message):
            return message
        case .decodingFailed(let message):
            return message
        case .transportFailed(let message):
            return message
        case .tokenExpired:
            return "The cached token expired."
        case .unsupportedMode(let message):
            return message
        }
    }
}

package protocol SpotifyAccessTokenProvider: Sendable {
    var mode: SpotifyClientMode { get }
    func fetchTokens() async throws -> SpotifySessionTokens
}

public protocol SpotifyTokenStore: Sendable {
    func loadTokens() async throws -> SpotifySessionTokens?
    func saveTokens(_ tokens: SpotifySessionTokens) async throws
    func clearTokens() async throws
}

public actor InMemorySpotifyTokenStore: SpotifyTokenStore {
    private var tokens: SpotifySessionTokens?

    public init(tokens: SpotifySessionTokens? = nil) {
        self.tokens = tokens
    }

    public func loadTokens() async throws -> SpotifySessionTokens? {
        tokens
    }

    public func saveTokens(_ tokens: SpotifySessionTokens) async throws {
        self.tokens = tokens
    }

    public func clearTokens() async throws {
        tokens = nil
    }
}
