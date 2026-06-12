// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 NetworkCore 对外暴露的统一请求客户端契约。

/// 描述同步请求、原始响应请求和流式连接的统一客户端能力。
public protocol NetworkClientProtocol {
    /// 发起类型化请求，并将响应解码为端点声明的响应模型。
    func request<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> E.Response

    /// 发起请求并返回原始 transport 响应，适合下载、调试或自定义解码场景。
    func requestData<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse

    /// 打开流式端点，并返回只读事件流。
    func stream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async -> AsyncThrowingStream<E.Event, Error>

    /// 打开完整流式会话，调用方可以发送消息、ping 或主动关闭连接。
    func openStream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async throws -> NetworkStreamSession<E.Event>
}

public extension NetworkClientProtocol {
    /// 无进度回调的类型化请求便捷入口。
    func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        try await request(endpoint, progressHandler: nil)
    }

    /// 无进度回调的原始响应请求便捷入口。
    func requestData<E: APIEndpoint>(_ endpoint: E) async throws -> TransportResponse {
        try await requestData(endpoint, progressHandler: nil)
    }
}
