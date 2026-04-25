import Foundation

public protocol AuthRefreshFailurePolicy {
    func shouldClearCredentials(after error: Error) -> Bool
}

public struct DefaultAuthRefreshFailurePolicy: AuthRefreshFailurePolicy {
    public init() {}

    public func shouldClearCredentials(after error: Error) -> Bool {
        switch ErrorMapper.map(error) {
        case .unauthorized:
            return true

        case let .httpStatus(code, _):
            return [401, 403].contains(code)

        case let .serverError(statusCode, _, _):
            return [401, 403].contains(statusCode)

        case let .business(code, _, _):
            return [401, 403].contains(code)

        default:
            return false
        }
    }
}
