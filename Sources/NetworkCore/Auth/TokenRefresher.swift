// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol TokenRefresher {
    func refreshTokens(using refreshToken: String) async throws -> AuthTokens
}
