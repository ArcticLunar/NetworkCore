// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum NetworkStreamOutboundMessage: Sendable, Equatable {
    case data(Data)
    case text(String)
}

public protocol NetworkStreamConnection: Sendable {
    var events: AsyncThrowingStream<NetworkStreamEvent, Error> { get }

    func send(_ message: NetworkStreamOutboundMessage) async throws
    func ping() async throws
    func close(code: Int?, reason: Data?) async
}

public final class NetworkStreamSession<Event: Sendable>: Sendable {
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
