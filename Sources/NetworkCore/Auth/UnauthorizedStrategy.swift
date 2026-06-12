// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 描述端点级别的 401 恢复行为。

/// 控制 `UnauthorizedPolicy` 在请求被判定为 unauthorized 后如何响应。
public enum UnauthorizedStrategy: Equatable, Sendable {
    /// 通知应用一次，并且不重试失败请求。
    case invalidateSessionOnce

    /// 刷新 token 并重试请求，直到达到配置的重试次数。
    case refreshAndRetry(maxRetryCount: Int)
}
