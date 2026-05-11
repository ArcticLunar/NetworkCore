// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol AuthCredentialsStore {
    func tokens() async throws -> AuthTokens?
    func save(tokens: AuthTokens) async
    func clear() async
}

public extension AuthCredentialsStore {
    func accessToken() async throws -> String? {
        try await tokens()?.accessToken
    }
}
