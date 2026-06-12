// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 实现 WebSocket 连接、收发、ping、关闭和重连。

import Foundation

/// URLSessionWebSocketTask 的可测试抽象。
public protocol WebSocketTasking: Sendable {
    func resume()
    func receive() async throws -> URLSessionWebSocketTask.Message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void)
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)

    var closeCode: URLSessionWebSocketTask.CloseCode { get }
    var closeReason: Data? { get }
}

/// 创建 WebSocket task 的抽象，便于测试替换。
public protocol WebSocketTaskLoading: Sendable {
    func makeTask(request: URLRequest) -> any WebSocketTasking
}

extension URLSessionWebSocketTask: WebSocketTasking {}

/// 基于 URLSession 的 WebSocket task loader。
public struct URLSessionWebSocketTaskLoader: WebSocketTaskLoading {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func makeTask(request: URLRequest) -> any WebSocketTasking {
        urlSession.webSocketTask(with: request)
    }
}

/// WebSocket 客户端，负责创建可重连的连接。
public final class WebSocketClient: @unchecked Sendable {
    private let loader: any WebSocketTaskLoading
    private let appLifecycleMonitor: any NetworkAppLifecycleMonitor

    public init(
        loader: any WebSocketTaskLoading = URLSessionWebSocketTaskLoader(),
        appLifecycleMonitor: any NetworkAppLifecycleMonitor = AlwaysActiveNetworkAppLifecycleMonitor()
    ) {
        self.loader = loader
        self.appLifecycleMonitor = appLifecycleMonitor
    }

    public func connect(
        _ request: URLRequest,
        reconnectPolicy: NetworkStreamReconnectPolicy? = nil,
        reconnectController: (any NetworkStreamReconnectControlling)? = nil
    ) -> any NetworkStreamConnection {
        URLSessionWebSocketConnection(
            request: request,
            loader: loader,
            reconnectPolicy: reconnectPolicy,
            appLifecycleMonitor: appLifecycleMonitor,
            reconnectController: reconnectController
        )
    }
}

private final class URLSessionWebSocketConnection: NetworkStreamConnection, @unchecked Sendable {
    // 1012 表示 service restart，通常适合按策略重连。
    private static let serviceRestartCloseCode = 1012

    let events: AsyncThrowingStream<NetworkStreamEvent, Error>

    private let request: URLRequest
    private let loader: any WebSocketTaskLoading
    private let reconnectPolicy: NetworkStreamReconnectPolicy?
    private let appLifecycleMonitor: any NetworkAppLifecycleMonitor
    private let reconnectController: (any NetworkStreamReconnectControlling)?
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<NetworkStreamEvent, Error>.Continuation?
    private var workerTask: Task<Void, Never>?
    private var currentTask: (any WebSocketTasking)?
    private var isClosed = false
    private var reconnectTimestamps: [Date] = []
    private var pendingReconnectMetadata: NetworkStreamReconnectMetadata?

    init(
        request: URLRequest,
        loader: any WebSocketTaskLoading,
        reconnectPolicy: NetworkStreamReconnectPolicy?,
        appLifecycleMonitor: any NetworkAppLifecycleMonitor,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) {
        self.request = request
        self.loader = loader
        self.reconnectPolicy = reconnectPolicy
        self.appLifecycleMonitor = appLifecycleMonitor
        self.reconnectController = reconnectController

        var capturedContinuation: AsyncThrowingStream<NetworkStreamEvent, Error>.Continuation?
        self.events = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation

        workerTask = Task {
            await run()
        }

        capturedContinuation?.onTermination = { @Sendable [weak self] _ in
            Task {
                await self?.close(code: nil, reason: nil)
            }
        }
    }

    func send(_ message: NetworkStreamOutboundMessage) async throws {
        let outbound: URLSessionWebSocketTask.Message
        switch message {
        case let .data(data):
            outbound = .data(data)
        case let .text(text):
            outbound = .string(text)
        }

        let task = try activeTask()
        try await task.send(outbound)
    }

    func ping() async throws {
        let task = try activeTask()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing(pongReceiveHandler: { error in
                if let error {
                    continuation.resume(throwing: ErrorMapper.map(error))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func close(code: Int?, reason: Data?) async {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code ?? 1000)
            ?? .normalClosure

        let shouldClose = lock.withLock { () -> Bool in
            guard isClosed == false else { return false }
            isClosed = true
            return true
        }

        guard shouldClose else {
            return
        }

        let task = lock.withLock { currentTask }
        task?.cancel(with: closeCode, reason: reason)
        workerTask?.cancel()
    }

    private func run() async {
        var reconnectAttempts = 0
        var reconnectOutcomePending = false

        while Task.isCancelled == false {
            let task = loader.makeTask(request: request)
            setCurrentTask(task)

            do {
                task.resume()
                continuation?.yield(.open(metadata: makeOpenMetadata()))
                if reconnectOutcomePending {
                    await reconnectController?.reconnectDidSucceed()
                    reconnectOutcomePending = false
                }

                while Task.isCancelled == false {
                    let message = try await task.receive()

                    switch message {
                    case let .data(data):
                        continuation?.yield(.message(data))

                    case let .string(text):
                        continuation?.yield(.message(Data(text.utf8)))

                    @unknown default:
                        continue
                    }
                }

                continuation?.finish()
                return
            } catch {
                let mappedError = ErrorMapper.map(error)

                if reconnectOutcomePending {
                    await reconnectController?.reconnectDidFail(with: mappedError)
                    reconnectOutcomePending = false
                }

                if Task.isCancelled || lock.withLock({ isClosed }) {
                    continuation?.finish()
                    return
                }

                if task.closeCode != .invalid {
                    let closeCode = Int(task.closeCode.rawValue)
                    let closeReason = task.closeReason
                    let reason = reconnectReason(forCloseCode: closeCode)
                    continuation?.yield(.closed(
                        code: closeCode,
                        reason: closeReason
                    ))

                    guard shouldReconnect(
                        afterCloseCode: closeCode,
                        reconnectAttempts: reconnectAttempts
                    ) else {
                        continuation?.finish()
                        return
                    }

                    reconnectAttempts += 1
                    do {
                        guard try await prepareForReconnect(
                            attempt: reconnectAttempts,
                            reason: reason
                        ) else {
                            continuation?.finish()
                            return
                        }
                        reconnectOutcomePending = true
                    } catch {
                        continuation?.finish()
                        return
                    }
                    continue
                }

                guard shouldReconnect(
                    after: mappedError,
                    reconnectAttempts: reconnectAttempts
                ) else {
                    if case .cancelled = mappedError {
                        continuation?.finish()
                    } else {
                        continuation?.finish(throwing: mappedError)
                    }
                    return
                }

                reconnectAttempts += 1
                do {
                    guard try await prepareForReconnect(
                        attempt: reconnectAttempts,
                        reason: .networkInterruption
                    ) else {
                        continuation?.finish(throwing: mappedError)
                        return
                    }
                    reconnectOutcomePending = true
                } catch {
                    continuation?.finish()
                    return
                }
            }
        }

        continuation?.finish()
    }

    private func activeTask() throws -> any WebSocketTasking {
        guard let task = lock.withLock({ currentTask }) else {
            throw NetworkError.invalidRequest("WebSocket is not connected")
        }

        return task
    }

    private func setCurrentTask(_ task: (any WebSocketTasking)?) {
        lock.withLock {
            currentTask = task
        }
    }

    private func awaitReconnectEligibility() async throws {
        if Task.isCancelled || lock.withLock({ isClosed }) {
            throw CancellationError()
        }

        let state = await appLifecycleMonitor.currentState()

        guard state != .active else {
            return
        }

        // WebSocket 重连前等待应用回到 active，避免后台状态下反复建连失败。
        await appLifecycleMonitor.waitUntilActive()

        if Task.isCancelled || lock.withLock({ isClosed }) {
            throw CancellationError()
        }
    }

    private func prepareForReconnect(
        attempt: Int,
        reason: NetworkStreamReconnectReason
    ) async throws -> Bool {
        var gateWaitDuration: TimeInterval = 0
        gateWaitDuration += try await measureWaitDuration {
            try await awaitReconnectEligibility()
        }
        gateWaitDuration += try await measureWaitDuration {
            try await reconnectController?.awaitReconnectReadiness()
        }

        let now = Date()
        pruneReconnectTimestamps(now: now)

        guard let delay = reconnectPolicy?.delay(
            forAttempt: attempt,
            timestamps: reconnectTimestamps,
            now: now
        ) else {
            return false
        }

        try await sleepForReconnect(delay: delay)
        gateWaitDuration += try await measureWaitDuration {
            try await awaitReconnectEligibility()
        }

        let timestamp = Date()
        pruneReconnectTimestamps(now: timestamp)
        reconnectTimestamps.append(timestamp)
        pendingReconnectMetadata = NetworkStreamReconnectMetadata(
            attempt: attempt,
            reason: reason,
            gateWaitDuration: gateWaitDuration,
            backoffDelay: delay
        )
        return true
    }

    private func shouldReconnect(
        after error: NetworkError,
        reconnectAttempts: Int
    ) -> Bool {
        guard let reconnectPolicy,
              reconnectAttempts < reconnectPolicy.maximumAttempts,
              lock.withLock({ isClosed }) == false else {
            return false
        }

        switch error {
        case .offline, .timeout, .cannotConnect, .dnsFailure, .transport:
            return reconnectPolicy.reasons.contains(.networkInterruption)
        default:
            return false
        }
    }

    private func shouldReconnect(
        afterCloseCode closeCode: Int,
        reconnectAttempts: Int
    ) -> Bool {
        guard let reconnectPolicy,
              reconnectAttempts < reconnectPolicy.maximumAttempts,
              lock.withLock({ isClosed }) == false else {
            return false
        }

        let reason = reconnectReason(forCloseCode: closeCode)
        return reconnectPolicy.reasons.contains(reason)
    }

    private func reconnectReason(forCloseCode closeCode: Int) -> NetworkStreamReconnectReason {
        switch closeCode {
        case URLSessionWebSocketTask.CloseCode.normalClosure.rawValue:
            return .normalClosure

        case URLSessionWebSocketTask.CloseCode.abnormalClosure.rawValue:
            return .abnormalClosure

        case Self.serviceRestartCloseCode:
            return .serviceRestart

        default:
            return .customCloseCode(closeCode)
        }
    }

    private func pruneReconnectTimestamps(now: Date) {
        guard let interval = reconnectPolicy?.budget?.interval,
              interval > 0 else {
            return
        }

        let windowStart = now.addingTimeInterval(-interval)
        reconnectTimestamps.removeAll { $0 < windowStart }
    }

    private func sleepForReconnect(delay: TimeInterval) async throws {
        guard delay > 0 else {
            return
        }

        try await Task.sleep(
            nanoseconds: UInt64(
                delay * 1_000_000_000
            )
        )
    }

    private func makeOpenMetadata() -> NetworkStreamMetadata? {
        defer { pendingReconnectMetadata = nil }

        guard let pendingReconnectMetadata else {
            return nil
        }

        return NetworkStreamMetadata(
            statusCode: nil,
            headers: nil,
            reconnect: pendingReconnectMetadata
        )
    }

    private func measureWaitDuration(
        _ operation: () async throws -> Void
    ) async throws -> TimeInterval {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
