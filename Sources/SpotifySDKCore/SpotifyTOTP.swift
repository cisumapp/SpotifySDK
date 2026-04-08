import Foundation
import CryptoKit

// MARK: - TOTP Generator

public enum SpotifyHMACAlgorithm {
    case sha1
    case sha256
    case sha512
}

public enum SpotifyTOTP {
    private static let spotifySeed: [UInt8] = [12, 56, 76, 33, 88, 44, 88, 33, 78, 78, 11, 66, 22, 22, 55, 69, 54]

    public static func generateSpotifyCode(at date: Date = Date()) -> String {
        let secret = spotifySecretBytes()
        return generate(secret: secret, at: date)
    }

    public static func generate(
        secret: Data,
        at date: Date,
        algorithm: SpotifyHMACAlgorithm = .sha1,
        digits: Int = 6,
        interval: TimeInterval = 30
    ) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / interval)
        let counterBytes = counter.bigEndianBytes
        let digest: Data

        switch algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secret)))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secret)))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secret)))
        }

        guard let lastByte = digest.last else {
            return String(repeating: "0", count: digits)
        }

        let offset = Int(lastByte & 0x0f)
        let binary = (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1] & 0xff) << 16)
            | (UInt32(digest[offset + 2] & 0xff) << 8)
            | UInt32(digest[offset + 3] & 0xff)

        var modulus = 1
        for _ in 0..<digits {
            modulus *= 10
        }

        let code = Int(binary % UInt32(modulus))
        return String(format: "%0*d", digits, code)
    }

    private static func spotifySecretBytes() -> Data {
        let transformed = spotifySeed.enumerated().map { index, value in
            String(value ^ UInt8((index % 33) + 9))
        }.joined()

        return Data(transformed.utf8)
    }
}

// MARK: - Live TOTP Source

public actor SpotifyLiveTOTPSource: SpotifyTOTPSource {
    private struct CachedSecret: Sendable {
        let version: Int
        let bytes: [UInt8]
        let expiry: Date
    }

    private let session: URLSession
    private var cachedSecret: CachedSecret?
    private let cacheTTL: TimeInterval = 15 * 60
    private let fallbackSecret: CachedSecret = CachedSecret(
        version: 18,
        bytes: [70, 60, 33, 57, 92, 120, 90, 33, 32, 62, 62, 55, 126, 93, 66, 35, 108, 68],
        expiry: .distantPast
    )

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func currentCode(at date: Date = Date()) async throws -> SpotifyTOTPCode {
        let secret = await latestSecret()
        let transformed = secret.bytes.enumerated().map { index, value in
            value ^ UInt8((index % 33) + 9)
        }
        let joined = transformed.map(String.init).joined()
        let code = SpotifyTOTP.generate(secret: Data(joined.utf8), at: date)
        return SpotifyTOTPCode(value: code, version: secret.version)
    }

    private func latestSecret() async -> CachedSecret {
        if let cachedSecret, Date() < cachedSecret.expiry {
            return cachedSecret
        }

        guard let url = URL(string: "https://code.thetadev.de/ThetaDev/spotify-secrets/raw/branch/main/secrets/secretDict.json") else {
            cachedSecret = fallbackSecret
            return fallbackSecret
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                cachedSecret = fallbackSecret
                return fallbackSecret
            }

            let decoded = try JSONSerialization.jsonObject(with: data, options: [])
            guard let secrets = decoded as? [String: [Int]],
                  let versionKey = secrets.keys.max(by: { Int($0) ?? 0 < Int($1) ?? 0 }),
                  let secretValues = secrets[versionKey],
                  !secretValues.isEmpty else {
                cachedSecret = fallbackSecret
                return fallbackSecret
            }

            let cached = CachedSecret(
                version: Int(versionKey) ?? fallbackSecret.version,
                bytes: secretValues.map { UInt8($0 & 0xff) },
                expiry: Date().addingTimeInterval(cacheTTL)
            )
            cachedSecret = cached
            return cached
        } catch {
            cachedSecret = fallbackSecret
            return fallbackSecret
        }
    }
}

// MARK: - Helpers

private extension UInt64 {
    var bigEndianBytes: Data {
        let value = bigEndian
        return withUnsafeBytes(of: value) { Data($0) }
    }
}
