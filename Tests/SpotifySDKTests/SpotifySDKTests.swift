import Foundation
import Testing
@testable import SpotifyOAuth
@testable import SpotifySDK
@testable import SpotifySDKCore

@Test func searchDesktopReturnsUrisAndPostsToPathfinder() async throws {
	let responseBody = #"""
{
    "data": {
        "searchV2": {
            "tracksV2": {
                "items": [
                    {
                        "item": {
                            "data": {
                                "id": "track-1",
                                "name": "Say It Ain't So",
                                "uri": "spotify:track:track-1",
                                "duration": { "totalMilliseconds": 185000 },
                                "contentRating": { "label": "NONE" },
                                "trackNumber": 3,
                                "trackMediaType": "AUDIO",
                                "artists": {
                                    "items": [
                                        {
                                            "profile": { "name": "Weezer" },
                                            "uri": "spotify:artist:artist-1"
                                        }
                                    ]
                                },
                                "albumOfTrack": {
                                    "id": "album-1",
                                    "name": "Blue Album",
                                    "uri": "spotify:album:album-1",
                                    "coverArt": {
                                        "sources": [
                                            {
                                                "height": 640,
                                                "url": "https://images.example.com/album-1.jpg",
                                                "width": 640
                                            }
                                        ]
                                    }
                                }
                            }
                        }
                    }
                ],
                "totalCount": 1
            },
            "albumsV2": {
                "items": [
                    {
                        "data": {
                            "id": "album-1",
                            "name": "Blue Album",
                            "uri": "spotify:album:album-1",
                            "type": "ALBUM",
                            "date": { "year": 1994 },
                            "artists": {
                                "items": [
                                    {
                                        "profile": { "name": "Weezer" },
                                        "uri": "spotify:artist:artist-1"
                                    }
                                ]
                            },
                            "coverArt": {
                                "sources": [
                                    {
                                        "height": 640,
                                        "url": "https://images.example.com/album-1.jpg",
                                        "width": 640
                                    }
                                ]
                            }
                        }
                    }
                ],
                "totalCount": 1
            },
            "playlists": {
                "items": [
                    {
                        "data": {
                            "id": "playlist-1",
                            "name": "Weezer Mix",
                            "uri": "spotify:playlist:playlist-1",
                            "description": "Weezer essentials",
                            "ownerV2": {
                                "data": {
                                    "name": "Spotify",
                                    "uri": "spotify:user:spotify",
                                    "username": "spotify"
                                }
                            },
                            "images": {
                                "items": [
                                    {
                                        "sources": [
                                            {
                                                "height": 640,
                                                "url": "https://images.example.com/playlist-1.jpg",
                                                "width": 640
                                            }
                                        ]
                                    }
                                ]
                            }
                        }
                    }
                ],
                "totalCount": 1
            },
            "artists": {
                "items": [
                    {
                        "data": {
                            "id": "artist-1",
                            "name": "Weezer",
                            "uri": "spotify:artist:artist-1",
                            "profile": { "name": "Weezer" },
                            "visuals": {
                                "avatarImage": {
                                    "sources": [
                                        {
                                            "height": 640,
                                            "url": "https://images.example.com/artist-1.jpg",
                                            "width": 640
                                        }
                                    ]
                                }
                            }
                        }
                    }
                ],
                "totalCount": 1
            }
        }
    }
}
"""#.data(using: .utf8)!

	let transport = MockTransport(
		responses: [
			.init(
				data: responseBody,
				response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
			)
		]
	)

	let tokens = SpotifySessionTokens(
		accessToken: SpotifyAccessToken(value: "pathfinder-access", expiresAt: Date().addingTimeInterval(3600)),
		clientToken: SpotifyClientToken(value: "pathfinder-client-token"),
		clientID: "client-id",
		isAnonymous: true
	)

    let sdk = await MainActor.run {
        SpotifySDK(
            mode: .anonymous,
            transport: transport,
            tokenStore: InMemorySpotifyTokenStore(tokens: tokens)
        )
    }
	let results = try await sdk.search.search("tyler, the creator", limit: 10, offset: 0, numberOfTopResults: 5)
    let mode = await MainActor.run { sdk.mode }

    #expect(mode == .anonymous)
	#expect(results.trackURIs == ["spotify:track:track-1"])
	#expect(results.albumURIs == ["spotify:album:album-1"])
	#expect(results.playlistURIs == ["spotify:playlist:playlist-1"])
	#expect(results.artistURIs == ["spotify:artist:artist-1"])

	let request = await transport.recordedRequests().first
	#expect(request?.httpMethod == "POST")
	#expect(request?.url?.path == "/pathfinder/v2/query")
	#expect(request?.value(forHTTPHeaderField: "App-Platform") == "WebPlayer")
	#expect(request?.value(forHTTPHeaderField: "client-token") == "pathfinder-client-token")

	let snapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: request?.httpBody ?? Data())
	#expect(snapshot.operationName == "searchDesktop")
	#expect(snapshot.variables.searchTerm == "tyler, the creator")
	#expect(snapshot.variables.limit == 10)
	#expect(snapshot.variables.offset == 0)
	#expect(snapshot.variables.numberOfTopResults == 5)
	#expect(snapshot.extensions.persistedQuery.sha256Hash == "8929d7a459f78787b6f0d557f14261faa4d5d8f6ca171cff5bb491ee239caa83")
}

@Test func searchSuggestionsReturnsUriHints() async throws {
	let responseBody = #"""
{
    "data": {
        "searchV2": {
            "topResultsV2": {
                "itemsV2": [
                    {
                        "item": {
                            "__typename": "SearchAutoCompleteEntity",
                            "data": {
                                "text": "tyler, the creator",
                                "uri": "spotify:search:tyler+the+creator"
                            }
                        }
                    },
                    {
                        "item": {
                            "__typename": "ArtistResponseWrapper",
                            "data": {
                                "name": "Tyler, The Creator",
                                "uri": "spotify:artist:4V8LLVI7PbaPR0K2TGSxFF",
                                "profile": { "name": "Tyler, The Creator" }
                            }
                        }
                    }
                ]
            }
        }
    }
}
"""#.data(using: .utf8)!

	let transport = MockTransport(
		responses: [
			.init(
				data: responseBody,
				response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
			)
		]
	)

	let tokens = SpotifySessionTokens(
		accessToken: SpotifyAccessToken(value: "pathfinder-access", expiresAt: Date().addingTimeInterval(3600)),
		clientToken: SpotifyClientToken(value: "pathfinder-client-token"),
		clientID: "client-id",
		isAnonymous: true
	)

    let sdk = await MainActor.run {
        SpotifySDK(
            mode: .anonymous,
            transport: transport,
            tokenStore: InMemorySpotifyTokenStore(tokens: tokens)
        )
    }
	let suggestions = try await sdk.search.searchSuggestions("tyler, the creator")

	#expect(suggestions.count == 2)
	#expect(suggestions.first?.title == "tyler, the creator")
	#expect(suggestions.first?.uri == "spotify:search:tyler+the+creator")
	#expect(suggestions.last?.title == "Tyler, The Creator")
	#expect(suggestions.last?.uri == "spotify:artist:4V8LLVI7PbaPR0K2TGSxFF")

	let request = await transport.recordedRequests().first
	#expect(request?.httpMethod == "POST")
	#expect(request?.url?.path == "/pathfinder/v2/query")

	let snapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: request?.httpBody ?? Data())
	#expect(snapshot.operationName == "searchSuggestions")
	#expect(snapshot.variables.query == "tyler, the creator")
	#expect(snapshot.variables.limit == 30)
	#expect(snapshot.variables.offset == 0)
	#expect(snapshot.variables.numberOfTopResults == 30)
	#expect(snapshot.extensions.persistedQuery.sha256Hash == "9fe3ad78e43a1684b3a9fabc741c5928928d4d30d7d8fd7fd193c7ebb4a544f4")
}

@Test func fetchAlbumAndArtistUseCorrectPathfinderPayloads() async throws {
    let albumResponseBody = #"""
{
    "data": {
        "albumUnion": {
            "__typename": "Album",
            "id": "album-1",
            "name": "Blue Album",
            "uri": "spotify:album:album-1",
            "type": "ALBUM",
            "albumType": "album",
            "date": { "year": 1994, "precision": "YEAR" },
            "artists": {
                "items": [
                    {
                        "id": "artist-1",
                        "profile": { "name": "Weezer" },
                        "uri": "spotify:artist:artist-1"
                    }
                ]
            },
            "coverArt": {
                "sources": [
                    {
                        "height": 640,
                        "url": "https://images.example.com/album-1.jpg",
                        "width": 640
                    }
                ]
            },
            "tracksV2": {
                "items": [
                    {
                        "data": {
                            "__typename": "Track",
                            "id": "track-1",
                            "name": "My Name Is Jonas",
                            "uri": "spotify:track:track-1",
                            "duration": { "totalMilliseconds": 245000 },
                            "contentRating": { "label": "NONE" },
                            "trackNumber": 1,
                            "trackMediaType": "AUDIO",
                            "artists": {
                                "items": [
                                    {
                                        "profile": { "name": "Weezer" },
                                        "uri": "spotify:artist:artist-1"
                                    }
                                ]
                            },
                            "albumOfTrack": {
                                "name": "Blue Album",
                                "uri": "spotify:album:album-1",
                                "artists": {
                                    "items": [
                                        {
                                            "profile": { "name": "Weezer" },
                                            "uri": "spotify:artist:artist-1"
                                        }
                                    ]
                                },
                                "coverArt": {
                                    "sources": [
                                        {
                                            "height": 640,
                                            "url": "https://images.example.com/album-1.jpg",
                                            "width": 640
                                        }
                                    ]
                                }
                            }
                        }
                    }
                ],
                "totalCount": 1,
                "limit": 50,
                "offset": 0
            }
        }
    }
}
"""#.data(using: .utf8)!
    let artistResponseBody = #"""
{
    "data": {
        "artistUnion": {
            "__typename": "Artist",
            "id": "artist-1",
            "name": "Weezer",
            "uri": "spotify:artist:artist-1",
            "profile": { "name": "Weezer" },
            "visuals": {
                "avatarImage": {
                    "sources": [
                        {
                            "height": 640,
                            "url": "https://images.example.com/artist-1.jpg",
                            "width": 640
                        }
                    ]
                }
            },
            "genres": ["alternative rock"],
            "popularity": 80
        }
    }
}
"""#.data(using: .utf8)!
    let transport = MockTransport(
        responses: [
            .init(
                data: albumResponseBody,
                response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
            ),
            .init(
                data: artistResponseBody,
                response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
            )
        ]
    )

    let tokens = SpotifySessionTokens(
        accessToken: SpotifyAccessToken(value: "pathfinder-access", expiresAt: Date().addingTimeInterval(3600)),
        clientToken: SpotifyClientToken(value: "pathfinder-client-token"),
        clientID: "client-id",
        isAnonymous: true
    )

    let sdk = await MainActor.run {
        SpotifySDK(
            mode: .anonymous,
            transport: transport,
            tokenStore: InMemorySpotifyTokenStore(tokens: tokens)
        )
    }

    let album = try await sdk.pathfinder.fetchAlbum(id: "album-1")
    let artist = try await sdk.pathfinder.fetchArtist(id: "artist-1")

    #expect(album.id == "album-1")
    #expect(album.name == "Blue Album")
    #expect(album.artists.count == 1)
    #expect(album.totalTracks == 1)
    #expect(artist.id == "artist-1")
    #expect(artist.name == "Weezer")
    #expect(artist.genres == ["alternative rock"])
    #expect(artist.popularity == 80)

    let requests = await transport.recordedRequests()
    #expect(requests.count == 2)

    let albumSnapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: requests[0].httpBody ?? Data())
    #expect(albumSnapshot.operationName == "getAlbum")
    #expect(albumSnapshot.variables.uri == "spotify:album:album-1")
    #expect(albumSnapshot.variables.locale == "")
    #expect(albumSnapshot.variables.offset == 0)
    #expect(albumSnapshot.variables.limit == 50)
    #expect(albumSnapshot.extensions.persistedQuery.sha256Hash == "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10")

    let artistSnapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: requests[1].httpBody ?? Data())
    #expect(artistSnapshot.operationName == "queryArtistOverview")
    #expect(artistSnapshot.variables.uri == "spotify:artist:artist-1")
    #expect(artistSnapshot.variables.locale == "")
    #expect(artistSnapshot.variables.preReleaseV2 == false)
    #expect(artistSnapshot.extensions.persistedQuery.sha256Hash == "7f86ff63e38c24973a2842b672abe44c910c1973978dc8a4a0cb648edef34527")
}

@Test func fetchHomeAndLibraryDecodeDynamicDocuments() async throws {
    let homeResponseBody = #"""
{
    "data": {
        "section": "home",
        "count": 3
    }
}
"""#.data(using: .utf8)!

    let libraryResponseBody = #"""
{
    "data": {
        "message": "library",
        "folders": ["Playlists"]
    }
}
"""#.data(using: .utf8)!

    let transport = MockTransport(
        responses: [
            .init(
                data: homeResponseBody,
                response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
            ),
            .init(
                data: libraryResponseBody,
                response: SpotifyHTTPResponse(statusCode: 200, headers: [:], url: URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!)
            )
        ]
    )

    let tokens = SpotifySessionTokens(
        accessToken: SpotifyAccessToken(value: "pathfinder-access", expiresAt: Date().addingTimeInterval(3600)),
        clientToken: SpotifyClientToken(value: "pathfinder-client-token"),
        clientID: "client-id",
        spotifyWebPlayerCookie: "sp_t-cookie-value",
        isAnonymous: true
    )

    let sdk = await MainActor.run {
        SpotifySDK(
            mode: .anonymous,
            transport: transport,
            tokenStore: InMemorySpotifyTokenStore(tokens: tokens)
        )
    }

    let home = try await sdk.pathfinder.fetchHome(timeZoneIdentifier: "Asia/Calcutta")
    let library = try await sdk.pathfinder.fetchLibraryV3()

    #expect(home.data?.objectValue?["section"]?.stringValue == "home")
    #expect(home.data?.objectValue?["count"]?.intValue == 3)
    #expect(library.data?.objectValue?["message"]?.stringValue == "library")
    #expect(library.data?.objectValue?["folders"]?.arrayValue?.first?.stringValue == "Playlists")

    let requests = await transport.recordedRequests()
    #expect(requests.count == 2)

    let homeSnapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: requests[0].httpBody ?? Data())
    #expect(homeSnapshot.operationName == "home")
    #expect(homeSnapshot.variables.homeEndUserIntegration == "INTEGRATION_WEB_PLAYER")
    #expect(homeSnapshot.variables.timeZone == "Asia/Calcutta")
    #expect(homeSnapshot.variables.sp_t == "sp_t-cookie-value")
    #expect(homeSnapshot.variables.facet == "")
    #expect(homeSnapshot.variables.sectionItemsLimit == 10)
    #expect(homeSnapshot.variables.includeEpisodeContentRatingsV2 == false)
    #expect(homeSnapshot.extensions.persistedQuery.sha256Hash == "23e37f2e58d82d567f27080101d36609009d8c3676457b1086cb0acc55b72a5d")

    let librarySnapshot = try JSONDecoder().decode(SpotifyPathfinderQuerySnapshot.self, from: requests[1].httpBody ?? Data())
    #expect(librarySnapshot.operationName == "libraryV3")
    #expect(librarySnapshot.variables.filters == ["Playlists"])
    #expect(librarySnapshot.variables.textFilter == "")
    #expect(librarySnapshot.variables.features == ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "PRERELEASES_V2", "EVENTS"])
    #expect(librarySnapshot.variables.limit == 50)
    #expect(librarySnapshot.variables.offset == 0)
    #expect(librarySnapshot.variables.flatten == false)
    #expect(librarySnapshot.variables.expandedFolders == [])
    #expect(librarySnapshot.variables.includeFoldersWhenFlattening == true)
    #expect(librarySnapshot.extensions.persistedQuery.sha256Hash == "973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3")
}

private struct SpotifyPathfinderQuerySnapshot: Decodable {
	let operationName: String
	let variables: Variables
	let extensions: Extensions

	struct Variables: Decodable {
		let searchTerm: String?
		let query: String?
        let uri: String?
        let locale: String?
        let preReleaseV2: Bool?
        let sp_t: String?
        let homeEndUserIntegration: String?
        let timeZone: String?
        let facet: String?
        let sectionItemsLimit: Int?
        let filters: [String]?
        let order: String?
        let textFilter: String?
        let features: [String]?
		let limit: Int?
		let offset: Int?
		let numberOfTopResults: Int?
		let includeAudiobooks: Bool?
		let includeArtistHasConcertsField: Bool?
		let includePreReleases: Bool?
		let includeAuthors: Bool?
		let includeEpisodeContentRatingsV2: Bool?
        let flatten: Bool?
        let expandedFolders: [String]?
        let folderUri: String?
        let includeFoldersWhenFlattening: Bool?
	}

	struct Extensions: Decodable {
		let persistedQuery: PersistedQuery
	}

	struct PersistedQuery: Decodable {
		let version: Int
		let sha256Hash: String
    }
}

private actor MockTransport: SpotifyTransport {
	struct Response: Sendable {
		let data: Data
		let response: SpotifyHTTPResponse
	}

	private var responses: [Response]
	private var requests: [URLRequest] = []

	init(responses: [Response]) {
		self.responses = responses
	}

	func send(_ request: URLRequest) async throws -> (Data, SpotifyHTTPResponse) {
		requests.append(request)
		guard !responses.isEmpty else {
			throw SpotifySDKError.invalidResponse
		}

        let response = responses.removeFirst()
        return (response.data, response.response)
	}

	func recordedRequests() -> [URLRequest] {
		requests
	}
}
