import Foundation

public struct SpotifyHTTPResponse: Sendable, Hashable {
    public var statusCode: Int
    public var headers: [String: String]
    public var url: URL?

    public init(statusCode: Int, headers: [String: String] = [:], url: URL? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
    }

    public var isSuccess: Bool {
        (200...299).contains(statusCode)
    }
}

public enum SpotifyHTTPMethod: String, Sendable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct SpotifyHTTPRequest: Sendable, Hashable {
    public var url: URL
    public var method: SpotifyHTTPMethod
    public var headers: [String: String]
    public var queryItems: [URLQueryItem]
    public var body: Data?

    public init(
        url: URL,
        method: SpotifyHTTPMethod = .get,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
    }

    public func urlRequest() -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        let existingQueryItems = components.queryItems ?? []
        let mergedQueryItems = existingQueryItems + queryItems
        if !mergedQueryItems.isEmpty {
            components.queryItems = mergedQueryItems
        }

        guard let resolvedURL = components.url else {
            return URLRequest(url: url)
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method.rawValue
        request.httpBody = body

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }
}

public protocol SpotifyTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, SpotifyHTTPResponse)
}

public struct URLSessionSpotifyTransport: SpotifyTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, SpotifyHTTPResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifySDKError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }

        return (
            data,
            SpotifyHTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                url: httpResponse.url
            )
        )
    }
}

public extension SpotifyAccessToken {
    var bearerHeaderValue: String {
        authorizationHeaderValue
    }
}