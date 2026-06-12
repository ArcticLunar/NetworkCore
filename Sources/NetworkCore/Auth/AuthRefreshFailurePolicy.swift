// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 token 刷新失败在什么情况下足以清理凭证。

import Foundation

/// 决定刷新失败后是否需要让本地凭证失效。
public protocol AuthRefreshFailurePolicy {
    /// 仅当错误明确表示 refresh token 或会话已失效时返回 true。
    func shouldClearCredentials(after error: Error) -> Bool
}

/// 对明确的鉴权失败清理凭证，对瞬时错误保留 token。
public struct DefaultAuthRefreshFailurePolicy: AuthRefreshFailurePolicy {
    public init() {}

    public func shouldClearCredentials(after error: Error) -> Bool {
        // 只有终态鉴权响应才会触发登出。网络失败、超时、DNS 失败、取消和 5xx
        // 都保留当前 token，让应用可以重试而不是强制重新登录。
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
