import Foundation

public struct AuthTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let accessTokenExpiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        accessTokenExpiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public extension AuthTokens {
    var hasUsableRefreshToken: Bool {
        guard let refreshToken else { return false }
        return refreshToken.isEmpty == false
    }

    func isAccessTokenExpiringSoon(
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        guard let accessTokenExpiresAt else { return false }
        return accessTokenExpiresAt.timeIntervalSince(now) <= leadTime
    }
}
