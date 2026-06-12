// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 在请求离开客户端之前，按端点要求补齐鉴权头。

import Foundation

/// 根据端点的鉴权要求注入认证头。
///
/// 如果传入 refresh 协调器，Bearer token 会优先通过它解析，从而在请求发出前完成
/// 提前刷新和并发刷新合并。
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

            // 协调器负责新鲜度检查和刷新去重；回退到 store 则让简单接入在
            // 由应用其他位置处理刷新时保持轻量。
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
