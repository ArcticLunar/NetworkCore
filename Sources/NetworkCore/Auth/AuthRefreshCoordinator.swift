// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public actor AuthRefreshCoordinator {
    private let credentialsStore: any AuthCredentialsStore
    private let refresher: any TokenRefresher
    private let refreshFailurePolicy: any AuthRefreshFailurePolicy
    private let refreshLeadTime: TimeInterval
    private var refreshTask: Task<AuthTokens, Error>?

    public init(
        credentialsStore: any AuthCredentialsStore,
        refresher: any TokenRefresher,
        refreshFailurePolicy: any AuthRefreshFailurePolicy = DefaultAuthRefreshFailurePolicy(),
        refreshLeadTime: TimeInterval = 60
    ) {
        self.credentialsStore = credentialsStore
        self.refresher = refresher
        self.refreshFailurePolicy = refreshFailurePolicy
        self.refreshLeadTime = refreshLeadTime
    }

    public func validAccessToken() async throws -> String? {
        guard let tokens = try await credentialsStore.tokens() else {
            return nil
        }

        if tokens.accessToken.isEmpty {
            return try await refreshToken(force: true)
        }

        guard shouldRefresh(tokens) else {
            return tokens.accessToken
        }

        return try await refreshToken(force: true)
    }

    public func refreshToken(force: Bool = false) async throws -> String {
        guard let tokens = try await credentialsStore.tokens() else {
            throw NetworkError.unauthorized
        }

        if force == false,
           shouldRefresh(tokens) == false,
           tokens.accessToken.isEmpty == false {
            return tokens.accessToken
        }

        guard let refreshToken = tokens.refreshToken,
              tokens.hasUsableRefreshToken else {
            await credentialsStore.clear()
            throw NetworkError.unauthorized
        }

        if let refreshTask {
            let refreshedTokens = try await refreshTask.value
            return refreshedTokens.accessToken
        }

        let task = Task<AuthTokens, Error> {
            try await refresher.refreshTokens(using: refreshToken)
        }

        refreshTask = task
        defer { refreshTask = nil }

        do {
            let refreshedTokens = try await task.value
            await credentialsStore.save(tokens: refreshedTokens)
            return refreshedTokens.accessToken
        } catch {
            if refreshFailurePolicy.shouldClearCredentials(after: error) {
                await credentialsStore.clear()
            }
            throw error
        }
    }

    public func refreshTokenIfNeeded() async throws -> String {
        try await refreshToken(force: false)
    }

    private func shouldRefresh(_ tokens: AuthTokens) -> Bool {
        tokens.isAccessTokenExpiringSoon(leadTime: refreshLeadTime)
    }
}
