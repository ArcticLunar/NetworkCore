// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 将 unauthorized 响应转换为一次会话失效处理，或一次 token 刷新重试。

import Foundation

/// 集中处理 401 的重试策略，覆盖登出和刷新后重试两类流程。
public struct UnauthorizedPolicy: RetryPolicy {
    private let defaultStrategy: UnauthorizedStrategy
    private let coordinator: UnauthorizedCoordinator
    private let refreshCoordinator: AuthRefreshCoordinator?

    public init(
        defaultStrategy: UnauthorizedStrategy = .invalidateSessionOnce,
        coordinator: UnauthorizedCoordinator,
        refreshCoordinator: AuthRefreshCoordinator? = nil
    ) {
        self.defaultStrategy = defaultStrategy
        self.coordinator = coordinator
        self.refreshCoordinator = refreshCoordinator
    }

    public func evaluate(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision {
        guard isUnauthorized(result) else {
            return .doNotRetry
        }

        // 端点级覆盖优先于全局默认值，让鉴权敏感流程可以独立选择刷新，
        // 或选择一次性会话失效处理。
        let strategy = context.options.unauthorizedStrategy ?? defaultStrategy

        switch strategy {
        case .invalidateSessionOnce:
            await coordinator.handleIfNeeded()
            return .doNotRetry

        case let .refreshAndRetry(maxRetryCount):
            // 协调器负责刷新去重。若刷新不可用，或端点已经达到重试次数上限，
            // 则改为只通知应用一次。
            guard retryCount < maxRetryCount, let refreshCoordinator else {
                await coordinator.handleIfNeeded()
                return .doNotRetry
            }

            do {
                _ = try await refreshCoordinator.refreshToken(force: true)
                return .retry(after: nil)
            } catch {
                await coordinator.handleIfNeeded()
                return .doNotRetry
            }
        }
    }

    private func isUnauthorized(_ result: Result<TransportResponse, Error>) -> Bool {
        switch result {
        case .success(let response):
            return response.response.statusCode == 401
        case .failure(let error):
            if case .unauthorized = ErrorMapper.map(error) {
                return true
            }
            return false
        }
    }
}
