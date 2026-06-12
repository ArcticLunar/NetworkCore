// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkClient 与底层网络库之间的 transport 抽象。

/// 执行已经构建好的 transport 请求。
public protocol NetworkTransport {
    /// 发送请求并返回原始 HTTP 响应。
    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse
}

public extension NetworkTransport {
    /// 无进度回调的发送便捷入口。
    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext
    ) async throws -> TransportResponse {
        try await send(
            request,
            context: context,
            progressHandler: nil
        )
    }
}
