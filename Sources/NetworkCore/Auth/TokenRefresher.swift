// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 `AuthRefreshCoordinator` 使用的业务侧 token 刷新钩子。

/// 通过业务认证接口刷新已过期或即将过期的 token 组合。
///
/// NetworkCore 会显式传入 refresh token，避免实现再次回读共享 store 并与协调器产生竞争。
public protocol TokenRefresher {
    /// 使用传入的 refresh token 换取可持久化的完整 token 组合。
    func refreshTokens(using refreshToken: String) async throws -> AuthTokens
}
