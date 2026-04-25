import Foundation

public struct AuthInterceptor: RequestInterceptor {
    private let credentialsStore: any AuthCredentialsStore
    private let refreshCoordinator: AuthRefreshCoordinator?
    private let defaultRequirement: AuthorizationRequirement

    public init(
        credentialsStore: any AuthCredentialsStore,
        refreshCoordinator: AuthRefreshCoordinator? = nil,
        defaultRequirement: AuthorizationRequirement = .bearerToken
    ) {
        self.credentialsStore = credentialsStore
        self.refreshCoordinator = refreshCoordinator
        self.defaultRequirement = defaultRequirement
    }

    public func adapt(
        _ request: URLRequest,
        context: NetworkRequestContext
    ) async throws -> URLRequest {
        let resolvedRequirement = resolve(context.authorization)

        switch resolvedRequirement {
        case .none:
            return request

        case .custom(let value):
            var request = request
            request.setValue(value, forHTTPHeaderField: "Authorization")
            return request

        case .bearerToken, .inheritGlobal:
            let token: String?

            if let refreshCoordinator {
                token = try await refreshCoordinator.validAccessToken()
            } else {
                token = try await credentialsStore.accessToken()
            }

            guard let token, token.isEmpty == false else {
                throw NetworkError.unauthorized
            }

            var request = request
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    private func resolve(_ requirement: AuthorizationRequirement) -> AuthorizationRequirement {
        if requirement == .inheritGlobal {
            return defaultRequirement
        }
        return requirement
    }
}
