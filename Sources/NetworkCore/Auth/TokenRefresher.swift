public protocol TokenRefresher {
    func refreshTokens(using refreshToken: String) async throws -> AuthTokens
}
