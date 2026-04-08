import Foundation
import SpotifySDKCore

public struct SpotifyAccountProfile: Sendable, Hashable {
	public var name: String
	public var username: String
	public var uri: String
	public var avatarImages: [SpotifyImage]
	public var avatarBackgroundColor: Int?

	public init(
		name: String,
		username: String,
		uri: String,
		avatarImages: [SpotifyImage] = [],
		avatarBackgroundColor: Int? = nil
	) {
		self.name = name
		self.username = username
		self.uri = uri
		self.avatarImages = avatarImages
		self.avatarBackgroundColor = avatarBackgroundColor
	}

	public var displayName: String {
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

		if !trimmedName.isEmpty, !trimmedUsername.isEmpty {
			return "\(trimmedName) (@\(trimmedUsername))"
		}

		if !trimmedName.isEmpty {
			return trimmedName
		}

		if !trimmedUsername.isEmpty {
			return "@\(trimmedUsername)"
		}

		return "Spotify account"
	}
}

public struct SpotifyLibraryPlaylistSummary: Identifiable, Sendable, Hashable {
	public var id: String { uri }

	public var uri: String
	public var name: String
	public var description: String?
	public var ownerUsername: String?
	public var ownerDisplayName: String?
	public var artworkURL: URL?
	public var isPublic: Bool?
	public var timestamp: Date?
	public var format: String?
	public var revision: String?
	public var trackCount: Int?

	public init(
		uri: String,
		name: String,
		description: String? = nil,
		ownerUsername: String? = nil,
		ownerDisplayName: String? = nil,
		artworkURL: URL? = nil,
		isPublic: Bool? = nil,
		timestamp: Date? = nil,
		format: String? = nil,
		revision: String? = nil,
		trackCount: Int? = nil
	) {
		self.uri = uri
		self.name = name
		self.description = description
		self.ownerUsername = ownerUsername
		self.ownerDisplayName = ownerDisplayName
		self.artworkURL = artworkURL
		self.isPublic = isPublic
		self.timestamp = timestamp
		self.format = format
		self.revision = revision
		self.trackCount = trackCount
	}
}

public struct SpotifyAccountClient: Sendable {
	private let pathfinder: SpotifyPathfinderClient
	private let auth: SpotifyAuthService
	private let transport: any SpotifyTransport

	public init(
		pathfinder: SpotifyPathfinderClient,
		auth: SpotifyAuthService,
		transport: any SpotifyTransport
	) {
		self.pathfinder = pathfinder
		self.auth = auth
		self.transport = transport
	}

	public func profile() async throws -> SpotifyAccountProfile {
		try await profileAttributes()
	}

	public func profileAttributes() async throws -> SpotifyAccountProfile {
		let data = try await pathfinder.performQuery(operation: .profileAttributes, variables: [:])
		let response = try JSONDecoder().decode(SpotifyAccountProfileAttributesResponse.self, from: data)

		guard let profile = response.data?.me?.profile else {
			throw SpotifySDKError.invalidResponse
		}

		return profile.toDomain()
	}

	public func playlists(limit: Int = 50) async throws -> [SpotifyLibraryPlaylistSummary] {
		let clampedLimit = max(1, limit)
		let profile = try await profileAttributes()
		let rootlist = try await fetchRootlistPlaylists(username: profile.username)

		if rootlist.isEmpty {
			return []
		}

		return Array(rootlist.prefix(clampedLimit))
	}

	public func libraryV3(
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
		try await pathfinder.fetchLibraryV3Page(
			filters: filters,
			order: order,
			textFilter: textFilter,
			features: features,
			limit: limit,
			offset: offset,
			flatten: flatten,
			expandedFolders: expandedFolders,
			folderUri: folderUri,
			includeFoldersWhenFlattening: includeFoldersWhenFlattening
		)
	}

	public func likedSongs(offset: Int = 0, limit: Int = 50) async throws -> SpotifyLikedSongsPage {
		try await pathfinder.fetchLibraryTracks(offset: offset, limit: limit)
	}

	private func fetchRootlistPlaylists(username: String) async throws -> [SpotifyLibraryPlaylistSummary] {
		let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
		guard let url = URL(string: "https://spclient.wg.spotify.com/playlist/v2/user/\(encodedUsername)/rootlist") else {
			throw SpotifySDKError.invalidResponse
		}

		let tokens = try await auth.currentSessionTokens()
		var headers: [String: String] = [
			"Authorization": tokens.authorizationHeaderValue,
			"Accept": "application/json",
			"Content-Type": "application/json;charset=UTF-8",
			"App-Platform": "WebPlayer",
			"User-Agent": Self.defaultUserAgent
		]

		if let clientToken = tokens.clientToken?.value {
			headers["client-token"] = clientToken
		}

		let request = SpotifyHTTPRequest(
			url: url,
			method: .get,
			headers: headers,
			queryItems: [
				URLQueryItem(name: "decorate", value: "revision,length,attributes,timestamp,owner,capabilities"),
				URLQueryItem(name: "bustCache", value: String(Int(Date().timeIntervalSince1970 * 1000)))
			]
		)

		let (data, response) = try await transport.send(request.urlRequest())
		guard response.isSuccess else {
			throw SpotifySDKError.transportFailed("Spotify rootlist request returned HTTP \(response.statusCode).")
		}

		let decoded = try JSONDecoder().decode(SpotifyRootlistResponse.self, from: data)
		return decoded.toDomain()
	}

	private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
}

private struct SpotifyAccountProfileAttributesResponse: Decodable {
	let data: SpotifyAccountProfileAttributesData?
}

private struct SpotifyAccountProfileAttributesData: Decodable {
	let me: SpotifyAccountProfileAttributesMe?
}

private struct SpotifyAccountProfileAttributesMe: Decodable {
	let profile: SpotifyAccountProfilePayload?
}

private struct SpotifyAccountProfilePayload: Decodable {
	let avatar: SpotifyAccountAvatar?
	let avatarBackgroundColor: Int?
	let name: String?
	let uri: String?
	let username: String?

	func toDomain() -> SpotifyAccountProfile {
		SpotifyAccountProfile(
			name: name ?? "",
			username: username ?? "",
			uri: uri ?? "",
			avatarImages: avatar?.sources.compactMap { $0.toDomain() } ?? [],
			avatarBackgroundColor: avatarBackgroundColor
		)
	}
}

private struct SpotifyAccountAvatar: Decodable {
	let sources: [SpotifyAccountAvatarSource]
}

private struct SpotifyAccountAvatarSource: Decodable {
	let height: Int?
	let url: String?
	let width: Int?

	func toDomain() -> SpotifyImage? {
		guard let url, let imageURL = URL(string: url) else { return nil }
		return SpotifyImage(url: imageURL, width: width, height: height)
	}
}

private struct SpotifyRootlistResponse: Decodable {
	let revision: String?
	let length: Int?
	let contents: SpotifyRootlistContents?
	let metaItems: [SpotifyRootlistMetaItem]?

	func toDomain() -> [SpotifyLibraryPlaylistSummary] {
		let contentItems = contents?.items ?? []
		let metadataItems = metaItems ?? []
		guard !contentItems.isEmpty else { return [] }

		var seen = Set<String>()
		var summaries: [SpotifyLibraryPlaylistSummary] = []
		summaries.reserveCapacity(contentItems.count)

		for (index, content) in contentItems.enumerated() {
			guard let uri = content.uri, uri.contains(":playlist:"), !uri.isEmpty else { continue }
			guard seen.insert(uri).inserted else { continue }

			let metadata = metadataItems[safe: index]
			let artworkURL = metadata?.attributes?.pictureSize?.first(where: { picture in
				picture.targetName?.lowercased() == "default"
			})?.url.flatMap(URL.init(string:)) ?? metadata?.attributes?.pictureSize?.first?.url.flatMap(URL.init(string:))
			let timestamp = parseMillisecondsTimestamp(content.attributes?.timestamp)
				?? parseMillisecondsTimestamp(metadata?.timestamp)

			summaries.append(
				SpotifyLibraryPlaylistSummary(
					uri: uri,
					name: normalizedRootlistPlaylistName(metadata?.attributes?.name),
					description: metadata?.attributes?.description,
					ownerUsername: metadata?.ownerUsername,
					ownerDisplayName: metadata?.ownerUsername,
					artworkURL: artworkURL,
					isPublic: content.attributes?.isPublic,
					timestamp: timestamp,
					format: metadata?.attributes?.format,
					revision: metadata?.revision,
					trackCount: metadata?.length
				)
			)
		}

		return summaries
	}
}

private struct SpotifyRootlistContents: Decodable {
	let pos: Int?
	let truncated: Bool?
	let items: [SpotifyRootlistContentItem]
}

private struct SpotifyRootlistContentItem: Decodable {
	let uri: String?
	let attributes: SpotifyRootlistContentAttributes?
}

private struct SpotifyRootlistContentAttributes: Decodable {
	let timestamp: String?
	let isPublic: Bool?

	private enum CodingKeys: String, CodingKey {
		case timestamp
		case isPublic = "public"
	}
}

private struct SpotifyRootlistMetaItem: Decodable {
	let revision: String?
	let attributes: SpotifyRootlistMetaAttributes?
	let length: Int?
	let timestamp: String?
	let ownerUsername: String?
}

private struct SpotifyRootlistMetaAttributes: Decodable {
	let name: String?
	let description: String?
	let collaborative: Bool?
	let format: String?
	let pictureSize: [SpotifyRootlistPictureSize]?
}

private struct SpotifyRootlistPictureSize: Decodable {
	let targetName: String?
	let url: String?
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		guard indices.contains(index) else { return nil }
		return self[index]
	}
}

private func normalizedRootlistPlaylistName(_ name: String?) -> String {
	let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
	return trimmed.isEmpty ? "Spotify Playlist" : trimmed
}

private func parseMillisecondsTimestamp(_ value: String?) -> Date? {
	guard let value, let milliseconds = Double(value) else { return nil }
	return Date(timeIntervalSince1970: milliseconds / 1000.0)
}