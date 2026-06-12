// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 endpoint 级 circuit breaker 的阈值和失败统计规则。

import Foundation

/// Circuit breaker 配置。
public struct CircuitBreaker: Sendable {
    /// 连续失败达到该阈值后进入 open 状态。
    public let failureThreshold: Int
    /// open 状态保持时间。
    public let openDuration: TimeInterval
    /// half-open 状态允许的并发探测请求数量。
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
        // 只统计服务端或网络基础设施类失败；业务失败、取消、离线限制不打开熔断器。
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
