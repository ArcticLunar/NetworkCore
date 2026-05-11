// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum ErrorMapper {
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
