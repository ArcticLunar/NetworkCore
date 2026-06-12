// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 对 unauthorized 处理进行串行化，避免同一波失败重复触发应用侧响应。

/// 确保在协调器重置之前，unauthorized 处理器只会被调用一次。
public actor UnauthorizedCoordinator {
    private let handler: any UnauthorizedHandler
    private var hasHandled = false

    public init(handler: any UnauthorizedHandler) {
        self.handler = handler
    }

    public func handleIfNeeded() async {
        guard hasHandled == false else { return }
        hasHandled = true
        await handler.handleUnauthorized()
    }

    /// 允许下一次 unauthorized 事件再次触发处理器。
    public func reset() {
        hasHandled = false
    }
}
