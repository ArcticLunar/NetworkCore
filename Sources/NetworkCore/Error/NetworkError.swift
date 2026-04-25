import Foundation

public enum NetworkError: Error {
    case invalidRequest(String)
    case invalidResponse
    case offline
    case timeout
    case cancelled
    case dnsFailure(underlying: Error)
    case cannotConnect(underlying: Error)
    case tlsFailure(underlying: Error)
    case serverTrustFailure(underlying: Error)
    case transport(underlying: Error)
    case networkAccessRestricted(NetworkAccessRestrictionReason)
    case circuitOpen(retryAfter: TimeInterval?)
    case httpStatus(code: Int, data: Data)
    case serverError(statusCode: Int, payload: ServerErrorPayload, data: Data)
    case unauthorized
    case business(code: Int, message: String, data: Data)
    case emptyData
    case unacceptableContentType(String?)
    case decoding(underlying: Error, data: Data)
    case retryExhausted(lastError: Error, retryCount: Int)
}
