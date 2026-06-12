// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 unauthorized 响应需要失效会话时的应用回调。

/// 处理终态 unauthorized 状态，通常用于清理应用会话或界面状态。
public protocol UnauthorizedHandler {
    /// 在一次被协调的 unauthorized 事件中只运行一次，直到协调器被重置。
    func handleUnauthorized() async
}

/// 仅需要重试行为、不需要额外副作用时使用的默认处理器。
public struct NoopUnauthorizedHandler: UnauthorizedHandler {
    public init() {}

    public func handleUnauthorized() async {}
}
