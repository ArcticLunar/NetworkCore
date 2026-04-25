import Foundation

public protocol SSEConnectionLoading: Sendable {
    func load(
        request: URLRequest
    ) async throws -> (lines: AsyncThrowingStream<String, Error>, response: URLResponse)
}

public final class URLSessionSSEConnectionLoader: SSEConnectionLoading, @unchecked Sendable {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func load(
        request: URLRequest
    ) async throws -> (lines: AsyncThrowingStream<String, Error>, response: URLResponse) {
        let (bytes, response) = try await urlSession.bytes(for: request)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return (lines, response)
    }
}

public final class SSEClient: @unchecked Sendable {
    private let loader: any SSEConnectionLoading
    private let defaultReconnectDelay: TimeInterval
    private let maximumReconnectAttempts: Int

    public init(
        loader: any SSEConnectionLoading = URLSessionSSEConnectionLoader(),
        defaultReconnectDelay: TimeInterval = 1,
        maximumReconnectAttempts: Int = 3
    ) {
        self.loader = loader
        self.defaultReconnectDelay = defaultReconnectDelay
        self.maximumReconnectAttempts = maximumReconnectAttempts
    }

    public func connect(
        _ request: URLRequest,
        reconnectPolicy: NetworkStreamReconnectPolicy? = nil,
        reconnectController: (any NetworkStreamReconnectControlling)? = nil
    ) -> any NetworkStreamConnection {
        SSEConnection(
            request: request,
            loader: loader,
            defaultReconnectDelay: defaultReconnectDelay,
            maximumReconnectAttempts: maximumReconnectAttempts,
            reconnectPolicy: reconnectPolicy,
            reconnectController: reconnectController
        )
    }
}

private final class SSEConnection: NetworkStreamConnection, @unchecked Sendable {
    private struct SSEParser {
        var id: String?
        var event: String?
        var dataLines: [String] = []
        var retry: Int?

        mutating func consume(line: String) -> ServerSentEvent? {
            guard line.isEmpty == false else {
                return dispatchIfNeeded()
            }

            guard line.hasPrefix(":") == false else {
                return nil
            }

            let components = line.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let field = String(components[0])
            let value = components.count > 1
                ? String(components[1]).trimmingPrefix(" ")
                : ""

            switch field {
            case "id":
                id = value
            case "event":
                event = value
            case "data":
                dataLines.append(value)
            case "retry":
                retry = Int(value)
            default:
                break
            }

            return nil
        }

        mutating func finish() -> ServerSentEvent? {
            dispatchIfNeeded()
        }

        private mutating func dispatchIfNeeded() -> ServerSentEvent? {
            guard id != nil
                    || event != nil
                    || dataLines.isEmpty == false
                    || retry != nil else {
                return nil
            }

            let resolvedEvent = ServerSentEvent(
                id: id,
                event: event,
                data: dataLines.joined(separator: "\n"),
                retry: retry
            )
            id = nil
            event = nil
            dataLines.removeAll(keepingCapacity: true)
            retry = nil
            return resolvedEvent
        }
    }

    let events: AsyncThrowingStream<NetworkStreamEvent, Error>

    private let loader: any SSEConnectionLoading
    private let baseRequest: URLRequest
    private let defaultReconnectDelay: TimeInterval
    private let maximumReconnectAttempts: Int
    private let reconnectPolicy: NetworkStreamReconnectPolicy?
    private let reconnectController: (any NetworkStreamReconnectControlling)?
    private let state = NSLock()

    private var continuation: AsyncThrowingStream<NetworkStreamEvent, Error>.Continuation?
    private var workerTask: Task<Void, Never>?
    private var isClosed = false
    private var reconnectTimestamps: [Date] = []
    private var pendingReconnectMetadata: NetworkStreamReconnectMetadata?

    init(
        request: URLRequest,
        loader: any SSEConnectionLoading,
        defaultReconnectDelay: TimeInterval,
        maximumReconnectAttempts: Int,
        reconnectPolicy: NetworkStreamReconnectPolicy?,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) {
        self.loader = loader
        self.baseRequest = request
        self.defaultReconnectDelay = defaultReconnectDelay
        self.maximumReconnectAttempts = maximumReconnectAttempts
        self.reconnectPolicy = reconnectPolicy
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
        throw NetworkError.invalidRequest(
            "SSE connections do not support outbound messages"
        )
    }

    func ping() async throws {
        throw NetworkError.invalidRequest(
            "SSE connections do not support ping"
        )
    }

    func close(code: Int?, reason: Data?) async {
        let shouldFinish = state.withLock { () -> Bool in
            guard isClosed == false else { return false }
            isClosed = true
            return true
        }

        guard shouldFinish else {
            return
        }

        workerTask?.cancel()
        continuation?.finish()
    }

    private func run() async {
        var lastEventID: String?
        var reconnectDelay = defaultReconnectDelay
        var reconnectAttempts = 0
        var reconnectOutcomePending = false

        while Task.isCancelled == false {
            do {
                let request = makeRequest(lastEventID: lastEventID)
                let loaded = try await loader.load(request: request)
                let response = try validate(response: loaded.response)

                continuation?.yield(.open(metadata: NetworkStreamMetadata(
                    statusCode: response.statusCode,
                    headers: headers(from: response),
                    reconnect: pendingReconnectMetadata
                )))
                pendingReconnectMetadata = nil
                if reconnectOutcomePending {
                    await reconnectController?.reconnectDidSucceed()
                    reconnectOutcomePending = false
                }

                var parser = SSEParser()

                for try await line in loaded.lines {
                    if let event = parser.consume(line: line) {
                        if let eventID = event.id, eventID.isEmpty == false {
                            lastEventID = eventID
                        }
                        if let retry = event.retry {
                            reconnectDelay = max(Double(retry) / 1000, 0)
                        }
                        continuation?.yield(.serverSentEvent(event))
                    }
                }

                if let event = parser.finish() {
                    if let eventID = event.id, eventID.isEmpty == false {
                        lastEventID = eventID
                    }
                    if let retry = event.retry {
                        reconnectDelay = max(Double(retry) / 1000, 0)
                    }
                    continuation?.yield(.serverSentEvent(event))
                }

                if state.withLock({ isClosed }) || Task.isCancelled {
                    continuation?.finish()
                    return
                }

                reconnectAttempts += 1
                guard reconnectAttempts <= maximumReconnectAttempts else {
                    continuation?.yield(.closed(code: nil, reason: nil))
                    continuation?.finish()
                    return
                }
                do {
                    guard try await prepareForReconnect(
                        attempt: reconnectAttempts,
                        baseDelay: reconnectDelay,
                        reason: .networkInterruption
                    ) else {
                        continuation?.yield(.closed(code: nil, reason: nil))
                        continuation?.finish()
                        return
                    }
                    reconnectOutcomePending = true
                } catch {
                    continuation?.finish()
                    return
                }
            } catch is CancellationError {
                continuation?.finish()
                return
            } catch let error as NetworkError {
                if reconnectOutcomePending {
                    await reconnectController?.reconnectDidFail(with: error)
                    reconnectOutcomePending = false
                }

                continuation?.finish(throwing: error)
                return
            } catch {
                let mappedError = ErrorMapper.map(error)
                if reconnectOutcomePending {
                    await reconnectController?.reconnectDidFail(with: mappedError)
                    reconnectOutcomePending = false
                }

                guard shouldReconnect(after: mappedError),
                      reconnectAttempts < maximumReconnectAttempts else {
                    continuation?.finish(throwing: mappedError)
                    return
                }

                reconnectAttempts += 1
                do {
                    guard try await prepareForReconnect(
                        attempt: reconnectAttempts,
                        baseDelay: reconnectDelay,
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

    private func makeRequest(lastEventID: String?) -> URLRequest {
        var request = baseRequest

        if request.value(forHTTPHeaderField: "Last-Event-ID") == nil,
           let lastEventID,
           lastEventID.isEmpty == false {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }

        return request
    }

    private func validate(response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpStatus(
                code: httpResponse.statusCode,
                data: Data()
            )
        }

        if let contentType = headerValue("Content-Type", in: httpResponse),
           contentType.lowercased().contains("text/event-stream") == false {
            throw NetworkError.unacceptableContentType(contentType)
        }

        return httpResponse
    }

    private func shouldReconnect(after error: NetworkError) -> Bool {
        switch error {
        case .offline, .timeout, .cannotConnect, .dnsFailure, .transport:
            return true
        default:
            return false
        }
    }

    private func sleepForReconnect(delay: TimeInterval) async throws {
        guard delay > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func prepareForReconnect(
        attempt: Int,
        baseDelay: TimeInterval,
        reason: NetworkStreamReconnectReason
    ) async throws -> Bool {
        let gateWaitDuration = try await measureWaitDuration {
            try await reconnectController?.awaitReconnectReadiness()
        }

        let now = Date()
        pruneReconnectTimestamps(now: now)

        let resolvedDelay: TimeInterval
        if let reconnectPolicy {
            guard let policyDelay = reconnectPolicy.delay(
                forAttempt: attempt,
                timestamps: reconnectTimestamps,
                now: now
            ) else {
                return false
            }
            resolvedDelay = max(baseDelay, policyDelay)
        } else {
            resolvedDelay = max(baseDelay, 0)
        }

        try await sleepForReconnect(delay: resolvedDelay)

        let timestamp = Date()
        pruneReconnectTimestamps(now: timestamp)
        reconnectTimestamps.append(timestamp)
        pendingReconnectMetadata = NetworkStreamReconnectMetadata(
            attempt: attempt,
            reason: reason,
            gateWaitDuration: gateWaitDuration,
            backoffDelay: resolvedDelay
        )
        return true
    }

    private func pruneReconnectTimestamps(now: Date) {
        guard let interval = reconnectPolicy?.budget?.interval,
              interval > 0 else {
            return
        }

        let threshold = now.addingTimeInterval(-interval)
        reconnectTimestamps.removeAll { $0 < threshold }
    }

    private func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { partialResult, item in
            guard let key = item.key as? String else { return }
            partialResult[key] = String(describing: item.value)
        }
    }

    private func headerValue(
        _ name: String,
        in response: HTTPURLResponse
    ) -> String? {
        headers(from: response)
            .first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?
            .value
    }

    private func measureWaitDuration(
        _ operation: () async throws -> Void
    ) async throws -> TimeInterval {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        guard first == prefix else {
            return self
        }

        return String(dropFirst())
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
