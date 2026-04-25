import Foundation

public protocol RequestInterceptor {
    func adapt(
        _ request: URLRequest,
        context: NetworkRequestContext
    ) async throws -> URLRequest
}
