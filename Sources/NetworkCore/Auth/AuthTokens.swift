// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义登录、请求适配和刷新流程共用的 token 值对象。

import Foundation

/// 表示请求使用的 access token，以及用于续期凭证的可选 refresh token。
public struct AuthTokens: Sendable, Equatable {
    /// 注入 `Authorization` 请求头的 Bearer token。
    public let accessToken: String

    /// 传给 `TokenRefresher` 的长生命周期 token；为空时表示无法执行刷新。
    public let refreshToken: String?

    /// 用于提前刷新的过期时间；`nil` 表示按非过期 token 处理。
    public let accessTokenExpiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        accessTokenExpiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public extension AuthTokens {
    /// 判断当前是否持有可用于刷新且非空的 refresh token。
    var hasUsableRefreshToken: Bool {
        guard let refreshToken else { return false }
        return refreshToken.isEmpty == false
    }

    /// 判断 access token 是否进入配置的提前刷新窗口。
    func isAccessTokenExpiringSoon(
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        guard let accessTokenExpiresAt else { return false }
        return accessTokenExpiresAt.timeIntervalSince(now) <= leadTime
    }
}
