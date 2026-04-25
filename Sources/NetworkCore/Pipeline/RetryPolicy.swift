import Foundation

public protocol RetryPolicy {
    func evaluate(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision
}
