// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义流式连接的收发接口和业务侧 session 包装。

import Foundation

/// 发送到 WebSocket 的出站消息。
public enum NetworkStreamOutboundMessage: Sendable, Equatable {
    case data(Data)
    case text(String)
}

/// 底层 SSE / WebSocket 连接抽象。
public protocol NetworkStreamConnection: Sendable {
    /// 连接产生的原始流事件。
    var events: AsyncThrowingStream<NetworkStreamEvent, Error> { get }

    func send(_ message: NetworkStreamOutboundMessage) async throws
    func ping() async throws
    func close(code: Int?, reason: Data?) async
}

/// 业务侧使用的流式会话，封装事件流和主动控制能力。
public final class NetworkStreamSession<Event: Sendable>: Sendable {
    /// 已映射成业务事件的流。
    public let events: AsyncThrowingStream<Event, Error>

    private let sendClosure: @Sendable (NetworkStreamOutboundMessage) async throws -> Void
    private let pingClosure: @Sendable () async throws -> Void
    private let closeClosure: @Sendable (Int?, Data?) async -> Void

    public init(
        events: AsyncThrowingStream<Event, Error>,
        send: @escaping @Sendable (NetworkStreamOutboundMessage) async throws -> Void,
        ping: @escaping @Sendable () async throws -> Void,
        close: @escaping @Sendable (Int?, Data?) async -> Void
    ) {
        self.events = events
        self.sendClosure = send
        self.pingClosure = ping
        self.closeClosure = close
    }

    public func send(_ message: NetworkStreamOutboundMessage) async throws {
        try await sendClosure(message)
    }

    public func send(text: String) async throws {
        try await send(.text(text))
    }

    public func send(data: Data) async throws {
        try await send(.data(data))
    }

    public func ping() async throws {
        try await pingClosure()
    }

    public func close(code: Int? = nil, reason: Data? = nil) async {
        await closeClosure(code, reason)
    }
}
