import Foundation

public struct NetworkRequestContext: Sendable {
    public let requestID: String
    public let environmentName: String
    public let path: String
    public let metricsPath: String
    public let method: HTTPMethod
    public let startTime: Date
    public let expectsEmptyResponseBody: Bool
    public let acceptableContentTypes: [String]
    public let authorization: AuthorizationRequirement
    public let options: RequestOptions
    public let allowsOfflineRecoveryRetry: Bool
    public let circuitBreakerIdentifier: String

    public init(
        requestID: String = UUID().uuidString,
        environmentName: String = "unknown",
        path: String,
        metricsPath: String? = nil,
        method: HTTPMethod,
        startTime: Date = Date(),
        expectsEmptyResponseBody: Bool = false,
        acceptableContentTypes: [String] = ["application/json"],
        authorization: AuthorizationRequirement,
        options: RequestOptions,
        allowsOfflineRecoveryRetry: Bool = false,
        circuitBreakerIdentifier: String? = nil
    ) {
        self.requestID = requestID
        self.environmentName = environmentName
        self.path = path
        self.metricsPath = metricsPath ?? Self.normalizeMetricsPath(path)
        self.method = method
        self.startTime = startTime
        self.expectsEmptyResponseBody = expectsEmptyResponseBody
        self.acceptableContentTypes = acceptableContentTypes
        self.authorization = authorization
        self.options = options
        self.allowsOfflineRecoveryRetry = allowsOfflineRecoveryRetry
        self.circuitBreakerIdentifier =
            circuitBreakerIdentifier
            ?? "\(environmentName)::\(method.rawValue)::\(path)"
    }

    private static func normalizeMetricsPath(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                let value = String(segment)

                if isUUIDLike(value) {
                    return ":uuid"
                }

                if isNumericIdentifier(value) {
                    return ":id"
                }

                if isOpaqueIdentifier(value) {
                    return ":token"
                }

                return value
            }
            .joined(separator: "/")
    }

    private static func isNumericIdentifier(_ segment: String) -> Bool {
        guard segment.isEmpty == false else { return false }
        return segment.allSatisfy(\.isNumber)
    }

    private static func isUUIDLike(_ segment: String) -> Bool {
        UUID(uuidString: segment) != nil
    }

    private static func isOpaqueIdentifier(_ segment: String) -> Bool {
        guard segment.count >= 24 else { return false }
        return segment.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }
}
