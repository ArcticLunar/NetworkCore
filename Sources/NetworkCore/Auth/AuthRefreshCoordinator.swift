// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 协调提前刷新和强制刷新，并保证凭证修改串行化。

import Foundation

/// 负责 token 新鲜度检查、刷新去重和凭证更新。
///
/// 该协调器保证同一时间只有一个刷新请求在执行。其他调用方会等待正在进行中的刷新，
/// 而不是用同一个 token 反复发起重复刷新。
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

        // 即使没有过期时间，只要 access token 为空，就视为不可用；
        // 当存在 refresh token 时，唯一安全路径就是刷新。
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
            // 没有可用的 refresh token 时，本地会话无法自愈。此时清理凭证，避免后续请求
            // 反复尝试不可能成功的刷新。
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
            // 失败策略会避免瞬时刷新失败直接变成强制登出，同时在明确鉴权拒绝时
            // 仍然清理凭证。
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
