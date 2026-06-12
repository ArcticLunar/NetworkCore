// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供默认生产 retry 策略，保护幂等请求并处理常见瞬时失败。

import Foundation

/// NetworkCore 默认 retry 策略。
public struct DefaultRetryPolicy: RetryPolicy {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitterRatio: Double

    private let retryableStatusCodes: Set<Int>
    private let retryableTransportCodes: Set<URLError.Code>

    public init(
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 4,
        jitterRatio: Double = 0.2,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableTransportCodes: Set<URLError.Code> = [
            .timedOut,
            .networkConnectionLost,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed
        ]
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterRatio = jitterRatio
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableTransportCodes = retryableTransportCodes
    }

    public func evaluate(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision {
        // 默认 retry 只覆盖幂等请求，避免自动重放非幂等写操作。
        guard context.options.isIdempotent else {
            return .doNotRetry
        }

        guard isRetryable(result, context: context) else {
            return .doNotRetry
        }

        guard retryCount < maxRetries else {
            return .retryExhausted
        }

        if case let .success(response) = result,
           let retryAfter = retryAfterDelay(from: response.response) {
            return .retry(after: retryAfter)
        }

        return .retry(after: backoffDelay(for: retryCount))
    }

    private func isRetryable(
        _ result: Result<TransportResponse, Error>,
        context: NetworkRequestContext
    ) -> Bool {
        switch result {
        case .success(let response):
            return retryableStatusCodes.contains(response.response.statusCode)

        case .failure(let error):
            return isRetryable(error, context: context)
        }
    }

    private func isRetryable(
        _ error: Error,
        context: NetworkRequestContext
    ) -> Bool {
        switch ErrorMapper.map(error) {
        case .timeout:
            return true

        case .cannotConnect:
            return true

        case .offline:
            return context.allowsOfflineRecoveryRetry

        case let .networkAccessRestricted(reason):
            if case .unavailable = reason {
                return context.allowsOfflineRecoveryRetry
            }

            return false

        case let .httpStatus(code, _):
            return retryableStatusCodes.contains(code)

        case let .serverError(statusCode, _, _):
            return retryableStatusCodes.contains(statusCode)

        case let .transport(underlying):
            if let urlError = underlying as? URLError {
                return retryableTransportCodes.contains(urlError.code)
            }
            return false

        default:
            return false
        }
    }

    private func retryAfterDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = headerValue(named: "Retry-After", in: response) else {
            return nil
        }

        if let seconds = TimeInterval(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(seconds, 0)
        }

        // Retry-After 同时支持秒数和 HTTP-date，这里兼容服务端两种常见返回。
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"

        guard let date = formatter.date(from: rawValue) else {
            return nil
        }

        return max(date.timeIntervalSinceNow, 0)
    }

    private func headerValue(named name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard let headerName = key as? String else { continue }
            guard headerName.caseInsensitiveCompare(name) == .orderedSame else { continue }
            return value as? String
        }

        return nil
    }

    private func backoffDelay(for retryCount: Int) -> TimeInterval {
        let exponentialDelay = min(baseDelay * pow(2, Double(retryCount)), maxDelay)
        guard exponentialDelay > 0, jitterRatio > 0 else {
            return exponentialDelay
        }

        let jitter = exponentialDelay * jitterRatio
        return max(
            exponentialDelay + Double.random(in: -jitter...jitter),
            0
        )
    }
}
