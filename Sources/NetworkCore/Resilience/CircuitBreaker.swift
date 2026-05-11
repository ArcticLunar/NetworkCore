// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct CircuitBreaker: Sendable {
    public let failureThreshold: Int
    public let openDuration: TimeInterval
    public let halfOpenMaxConcurrentProbes: Int

    public init(
        failureThreshold: Int = 3,
        openDuration: TimeInterval = 30,
        halfOpenMaxConcurrentProbes: Int = 1
    ) {
        self.failureThreshold = max(failureThreshold, 1)
        self.openDuration = max(openDuration, 0)
        self.halfOpenMaxConcurrentProbes = max(halfOpenMaxConcurrentProbes, 1)
    }

    func shouldCountFailure(_ error: Error) -> Bool {
        switch ErrorMapper.map(error) {
        case .timeout,
             .dnsFailure,
             .cannotConnect,
             .tlsFailure,
             .serverTrustFailure,
             .transport,
             .invalidResponse:
            return true

        case let .httpStatus(code, _):
            return code == 408 || code == 429 || code >= 500

        case let .serverError(statusCode, _, _):
            return statusCode == 408 || statusCode == 429 || statusCode >= 500

        case let .retryExhausted(lastError, _):
            return shouldCountFailure(lastError)

        case .invalidRequest,
             .offline,
             .cancelled,
             .networkAccessRestricted,
             .unauthorized,
             .business,
             .emptyData,
             .unacceptableContentType,
             .decoding,
             .circuitOpen:
            return false
        }
    }
}
