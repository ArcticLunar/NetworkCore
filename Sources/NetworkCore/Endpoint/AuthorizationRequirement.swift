// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 描述端点是否需要鉴权以及如何生成 Authorization 头。

/// 单个端点的鉴权策略。
public enum AuthorizationRequirement: Equatable, Sendable {
    /// 不附加鉴权头。
    case none
    /// 使用当前 access token 注入 Bearer 鉴权头。
    case bearerToken
    /// 使用调用方提供的完整 Authorization 值。
    case custom(String)
    /// 继承 `NetworkConfiguration.defaultAuthorizationRequirement`。
    case inheritGlobal
}
