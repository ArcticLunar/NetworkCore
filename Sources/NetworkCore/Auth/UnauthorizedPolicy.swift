// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

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

        let strategy = context.options.unauthorizedStrategy ?? defaultStrategy

        switch strategy {
        case .invalidateSessionOnce:
            await coordinator.handleIfNeeded()
            return .doNotRetry

        case let .refreshAndRetry(maxRetryCount):
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
