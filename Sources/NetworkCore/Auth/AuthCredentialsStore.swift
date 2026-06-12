// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义由业务侧持有的凭证 store 契约，供鉴权拦截器和刷新协调器使用。

/// 在 NetworkCore 外部存取当前认证 token。
///
/// 实现通常会桥接 Keychain、加密 store 或业务会话 store。NetworkCore
/// 只依赖协议，避免框架直接持有产品侧的凭证持久化细节。
public protocol AuthCredentialsStore {
    /// 返回最新 token 组合；未登录时返回 `nil`。
    func tokens() async throws -> AuthTokens?

    /// 在登录或刷新成功后持久化新签发的 token 组合。
    func save(tokens: AuthTokens) async

    /// 在认证失败已确认不可恢复时清理本地凭证。
    func clear() async
}

public extension AuthCredentialsStore {
    /// 仅需要 Bearer token 的调用方使用的便捷读取入口。
    func accessToken() async throws -> String? {
        try await tokens()?.accessToken
    }
}
