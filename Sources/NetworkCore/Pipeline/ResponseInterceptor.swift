// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义响应校验和解码前的异步拦截钩子。

/// 在响应进入 validator 和 decoder 前执行副作用或额外检查。
public protocol ResponseInterceptor {
    /// 接收原始响应；抛错会中断后续校验和解码流程。
    func didReceive(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) async throws
}
