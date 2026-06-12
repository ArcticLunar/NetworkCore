// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 根据流类型分派到 SSE 或 WebSocket 客户端。

import Foundation

/// 打开底层流式连接的 transport 抽象。
public protocol NetworkStreamTransport: Sendable {
    func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection
}

/// 默认流式 transport 实现。
public final class DefaultNetworkStreamTransport: NetworkStreamTransport, @unchecked Sendable {
    private let sseClient: SSEClient
    private let webSocketClient: WebSocketClient

    public init(
        sseClient: SSEClient = SSEClient(),
        webSocketClient: WebSocketClient = WebSocketClient()
    ) {
        self.sseClient = sseClient
        self.webSocketClient = webSocketClient
    }

    public func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection {
        switch kind {
        case .serverSentEvents:
            return sseClient.connect(
                request.urlRequest,
                reconnectPolicy: context.options.streamReconnectPolicy,
                reconnectController: reconnectController
            )

        case .webSocket:
            return webSocketClient.connect(
                request.urlRequest,
                reconnectPolicy: context.options.streamReconnectPolicy,
                reconnectController: reconnectController
            )
        }
    }
}
