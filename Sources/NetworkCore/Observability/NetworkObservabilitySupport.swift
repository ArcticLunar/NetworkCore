import Foundation

enum NetworkObservabilitySupport {
    static func category(for error: Error) -> String {
        ErrorMapper.map(error).observabilityCategory
    }

    static func safeErrorDescription(for error: Error) -> String {
        let mappedError = ErrorMapper.map(error)
        var components = ["category=\(mappedError.observabilityCategory)"]

        if let statusCode = statusCode(from: error) {
            components.append("status_code=\(statusCode)")
        }

        if let failure = error as? NetworkFailure {
            components.append("request_id=\(failure.context.requestID)")

            switch failure.error {
            case let .serverError(_, payload, _):
                appendPayloadSummary(payload, to: &components)

            case let .business(code, _, _):
                components.append("business_code=\(code)")

            case let .retryExhausted(lastError, retryCount):
                components.append("retry_count=\(retryCount)")
                components.append("last_error_category=\(category(for: lastError))")

            case let .networkAccessRestricted(reason):
                components.append("restriction=\(safeRestrictionDescription(reason))")

            default:
                break
            }

            return components.joined(separator: " ")
        }

        switch mappedError {
        case let .serverError(_, payload, _):
            appendPayloadSummary(payload, to: &components)

        case let .business(code, _, _):
            components.append("business_code=\(code)")

        case let .retryExhausted(lastError, retryCount):
            components.append("retry_count=\(retryCount)")
            components.append("last_error_category=\(category(for: lastError))")

        case let .networkAccessRestricted(reason):
            components.append("restriction=\(safeRestrictionDescription(reason))")

        default:
            break
        }

        return components.joined(separator: " ")
    }

    static func safeBackgroundFailureDescription(
        reason: BackgroundTransferFailureReason,
        error: Error? = nil
    ) -> String {
        var components = ["reason=\(reason.metricsValue)"]

        if let statusCode = reason.statusCode {
            components.append("status_code=\(statusCode)")
        }

        guard let error else {
            return components.joined(separator: " ")
        }

        let safeErrorComponents = safeErrorDescription(for: error)
            .split(separator: " ")
            .map(String.init)

        for component in safeErrorComponents {
            if component.hasPrefix("status_code="),
               reason.statusCode != nil {
                continue
            }

            if components.contains(component) == false {
                components.append(component)
            }
        }

        return components.joined(separator: " ")
    }

    static func statusCode(from error: Error) -> Int? {
        if let failure = error as? NetworkFailure, let statusCode = failure.context.statusCode {
            return statusCode
        }

        switch ErrorMapper.map(error) {
        case let .httpStatus(code, _):
            return code
        case let .serverError(statusCode, _, _):
            return statusCode
        default:
            return nil
        }
    }

    static func responseHeaders(from error: Error) -> [String: String]? {
        (error as? NetworkFailure)?.context.responseHeaders
    }

    static func responseBody(from error: Error) -> Data? {
        switch ErrorMapper.map(error) {
        case let .httpStatus(_, data):
            return data
        case let .serverError(_, _, data):
            return data
        case let .business(_, _, data):
            return data
        case let .decoding(_, data):
            return data
        default:
            return nil
        }
    }

    static func isUnauthorized(_ error: Error) -> Bool {
        if let statusCode = statusCode(from: error), statusCode == 401 {
            return true
        }

        if case .unauthorized = ErrorMapper.map(error) {
            return true
        }

        return false
    }

    static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { partialResult, item in
            guard let key = item.key as? String else { return }
            partialResult[key] = String(describing: item.value)
        }
    }

    static func headerValue(_ name: String, in headers: [String: String]?) -> String? {
        headers?.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private static func appendPayloadSummary(
        _ payload: ServerErrorPayload,
        to components: inout [String]
    ) {
        if let code = payload.code {
            components.append("server_code=\(code)")
        }

        if let requestID = payload.requestID,
           requestID.isEmpty == false {
            components.append("server_request_id=\(requestID)")
        }

        if let traceID = payload.traceID,
           traceID.isEmpty == false {
            components.append("trace_id=\(traceID)")
        }
    }

    private static func safeRestrictionDescription(
        _ reason: NetworkAccessRestrictionReason
    ) -> String {
        switch reason {
        case .unavailable:
            return "unavailable"
        case .requiresNonCellularConnection:
            return "requires_non_cellular_connection"
        case .constrainedNetwork:
            return "constrained_network"
        case .expensiveNetwork:
            return "expensive_network"
        case let .expensiveUploadTooLarge(maxBytes, actualBytes):
            return "expensive_upload_too_large:\(maxBytes):\(actualBytes)"
        case let .constrainedUploadTooLarge(maxBytes, actualBytes):
            return "constrained_upload_too_large:\(maxBytes):\(actualBytes)"
        }
    }
}

private extension NetworkError {
    var observabilityCategory: String {
        switch self {
        case .invalidRequest:
            return "invalid_request"
        case .invalidResponse:
            return "invalid_response"
        case .offline:
            return "offline"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .dnsFailure:
            return "dns_failure"
        case .cannotConnect:
            return "cannot_connect"
        case .tlsFailure:
            return "tls_failure"
        case .serverTrustFailure:
            return "server_trust_failure"
        case .transport:
            return "transport"
        case .networkAccessRestricted:
            return "network_access_restricted"
        case .circuitOpen:
            return "circuit_open"
        case .httpStatus:
            return "http_status"
        case .serverError:
            return "server_error"
        case .unauthorized:
            return "unauthorized"
        case .business:
            return "business"
        case .emptyData:
            return "empty_data"
        case .unacceptableContentType:
            return "unacceptable_content_type"
        case .decoding:
            return "decoding"
        case .retryExhausted:
            return "retry_exhausted"
        }
    }
}
