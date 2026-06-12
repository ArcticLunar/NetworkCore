// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 将 Foundation、Alamofire 和框架内部错误收敛为 NetworkError / NetworkFailure。

import Foundation

/// 错误映射工具，保证上层看到稳定的错误分类和上下文。
public enum ErrorMapper {
    /// 将任意错误映射为 `NetworkError`，保留已映射错误不重复包装。
    public static func map(_ error: Error) -> NetworkError {
        if let failure = error as? NetworkFailure {
            return failure.error
        }

        if let networkError = error as? NetworkError {
            return networkError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            return map(urlError)
        }

        return .transport(underlying: error)
    }

    /// 将任意错误映射为带请求上下文的 `NetworkFailure`。
    public static func map(
        _ error: Error,
        context: NetworkRequestContext,
        retryCount: Int,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        duration: TimeInterval? = nil
    ) -> NetworkFailure {
        if let failure = error as? NetworkFailure {
            return failure
        }

        return NetworkFailure(
            error: map(error),
            context: NetworkErrorContext(
                requestID: context.requestID,
                environmentName: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: statusCode ?? extractedStatusCode(from: error),
                duration: duration,
                retryCount: retryCount,
                responseHeaders: responseHeaders
            )
        )
    }

    /// 将 URLError 细分为更利于业务处理和排障的网络错误。
    static func map(_ error: URLError) -> NetworkError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet:
            return .offline
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure(underlying: error)
        case .cannotConnectToHost:
            return .cannotConnect(underlying: error)
        case .secureConnectionFailed:
            return .tlsFailure(underlying: error)
        case .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .serverTrustFailure(underlying: error)
        default:
            return .transport(underlying: error)
        }
    }

    private static func extractedStatusCode(from error: Error) -> Int? {
        switch map(error) {
        case let .httpStatus(code, _):
            return code
        case let .serverError(statusCode, _, _):
            return statusCode
        default:
            return nil
        }
    }
}
