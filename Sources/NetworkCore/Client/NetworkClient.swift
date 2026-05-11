// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public actor NetworkClient: NetworkClientProtocol {
    private final class EndpointStreamMapper<E: StreamingEndpoint>: @unchecked Sendable {
        private let endpoint: E

        init(endpoint: E) {
            self.endpoint = endpoint
        }

        func map(_ event: NetworkStreamEvent) throws -> E.Event? {
            try endpoint.mapStreamEvent(event)
        }
    }

    private struct RequestExecutionResult {
        let response: TransportResponse
        let retryCount: Int
    }

    private struct RequestExecutionError: Error {
        let underlying: Error
        let retryCount: Int
        let statusCode: Int?
        let responseHeaders: [String: String]?
        let request: URLRequest?
    }

    private enum RetryApplicationResult {
        case noRetry
        case didRetry
        case exhausted
    }

    private let configuration: NetworkConfiguration
    private let transport: any NetworkTransport
    private let streamTransport: any NetworkStreamTransport

    public init(
        configuration: NetworkConfiguration,
        transport: any NetworkTransport,
        streamTransport: (any NetworkStreamTransport)? = nil
    ) {
        self.configuration = configuration
        self.transport = transport
        self.streamTransport = streamTransport ?? DefaultNetworkStreamTransport(
            webSocketClient: WebSocketClient(
                appLifecycleMonitor: configuration.appLifecycleMonitor
            )
        )
    }

    public func request<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> E.Response {
        let context = makeContext(for: endpoint)
        notifyStartIfNeeded(context)

        var circuitBreakerAdmission: EndpointFailureTracker.Admission?
        var requestSize: Int?
        var result: RequestExecutionResult?

        do {
            circuitBreakerAdmission = try await acquireCircuitBreakerAdmissionIfNeeded(
                for: context
            )
            let execution = try await perform(
                endpoint: endpoint,
                context: context,
                progressHandler: progressHandler
            )
            result = execution.0
            requestSize = execution.1

            let responseBody: E.Response

            guard let result else {
                throw NetworkError.invalidResponse
            }

            if result.response.data.isEmpty, E.Response.self == EmptyResponse.self {
                responseBody = EmptyResponse() as! E.Response
            } else {
                let decodedResponse = try configuration.responseDecoder.decode(
                    E.Response.self,
                    from: result.response,
                    decoder: endpoint.decoder,
                    context: context,
                    policy: endpoint.decodingPolicy
                        ?? configuration.defaultDecodingPolicy
                )
                responseBody = decodedResponse.value

                if decodedResponse.warningCount > 0 {
                    notifyDecodingDegradedIfNeeded(
                        context: context,
                        warningCount: decodedResponse.warningCount
                    )
                }
            }

            await recordCircuitBreakerSuccessIfNeeded(
                circuitBreakerAdmission,
                context: context
            )
            notifyFinishIfNeeded(.success(
                context: context,
                request: result.response.request,
                response: result.response,
                metadata: NetworkEventMetadata(
                    duration: Date().timeIntervalSince(context.startTime),
                    retryCount: result.retryCount,
                    requestSize: requestSize,
                    responseSize: responseSize(of: result.response)
                )
            ))

            return responseBody
        } catch {
            let failure = makeFailure(
                from: error,
                context: context,
                requestSize: requestSize,
                executionResult: result
            )
            await recordCircuitBreakerFailureIfNeeded(
                failure.failure,
                admission: circuitBreakerAdmission,
                context: context
            )
            notifyFinishIfNeeded(.failure(
                context: context,
                request: request(from: error) ?? result?.response.request,
                error: failure.failure,
                metadata: failure.metadata
            ))
            throw failure.failure
        }
    }

    public func requestData<E: APIEndpoint>(
        _ endpoint: E,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        let context = makeContext(for: endpoint)
        notifyStartIfNeeded(context)
        var circuitBreakerAdmission: EndpointFailureTracker.Admission?
        var requestSize: Int?
        var result: RequestExecutionResult?

        do {
            circuitBreakerAdmission = try await acquireCircuitBreakerAdmissionIfNeeded(
                for: context
            )
            let execution = try await perform(
                endpoint: endpoint,
                context: context,
                progressHandler: progressHandler
            )
            result = execution.0
            requestSize = execution.1

            guard let result else {
                throw NetworkError.invalidResponse
            }

            await recordCircuitBreakerSuccessIfNeeded(
                circuitBreakerAdmission,
                context: context
            )
            notifyFinishIfNeeded(.success(
                context: context,
                request: result.response.request,
                response: result.response,
                metadata: NetworkEventMetadata(
                    duration: Date().timeIntervalSince(context.startTime),
                    retryCount: result.retryCount,
                    requestSize: requestSize,
                    responseSize: responseSize(of: result.response)
                )
            ))

            return result.response
        } catch {
            let failure = makeFailure(
                from: error,
                context: context,
                requestSize: requestSize,
                executionResult: result
            )
            await recordCircuitBreakerFailureIfNeeded(
                failure.failure,
                admission: circuitBreakerAdmission,
                context: context
            )
            notifyFinishIfNeeded(.failure(
                context: context,
                request: request(from: error) ?? result?.response.request,
                error: failure.failure,
                metadata: failure.metadata
            ))
            throw failure.failure
        }
    }

    public func stream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async -> AsyncThrowingStream<E.Event, Error> {
        do {
            return try await openStream(endpoint).events
        } catch {
            let context = makeContext(for: endpoint)
            return failedStream(error, context: context)
        }
    }

    public func openStream<E: StreamingEndpoint>(
        _ endpoint: E
    ) async throws -> NetworkStreamSession<E.Event> {
        let context = makeContext(for: endpoint)
        notifyStartIfNeeded(context)

        let builtRequest: TransportRequest

        do {
            builtRequest = try RequestBuilder.build(
                endpoint: endpoint,
                configuration: configuration
            )
        } catch {
            throw ErrorMapper.map(
                error,
                context: context,
                retryCount: 0
            )
        }

        let preparedRequest = prepareStreamRequest(
            builtRequest,
            kind: endpoint.streamKind
        )
        let mapper = EndpointStreamMapper(endpoint: endpoint)
        var circuitBreakerAdmission: EndpointFailureTracker.Admission?

        do {
            circuitBreakerAdmission = try await acquireCircuitBreakerAdmissionIfNeeded(
                for: context
            )
            let adaptedRequest = try await adapt(
                preparedRequest,
                context: context
            )
            try await awaitEligibleNetworkIfNeeded(
                for: adaptedRequest,
                context: context
            )

            let connection = try await streamTransport.openConnection(
                adaptedRequest,
                kind: endpoint.streamKind,
                context: context,
                reconnectController: makeReconnectControllerIfNeeded(
                    for: endpoint.streamKind,
                    context: context
                )
            )

            let mappedEvents = AsyncThrowingStream<E.Event, Error> { continuation in
                let task = Task {
                    var eventCount = 0
                    var messageCount = 0
                    var messageBytes = 0
                    var closeCode: Int?

                    do {
                        var iterator = connection.events.makeAsyncIterator()

                        while let event = try await iterator.next() {
                            eventCount += 1

                            switch event {
                            case let .open(metadata):
                                self.notifyStreamOpenIfNeeded(
                                    context: context,
                                    metadata: metadata
                                )

                            case let .message(data):
                                messageCount += 1
                                messageBytes += data.count
                                self.notifyStreamMessageIfNeeded(
                                    context: context,
                                    metadata: NetworkStreamMessageMetadata(
                                        sequenceNumber: messageCount,
                                        kind: .webSocketMessage,
                                        bytes: data.count
                                    )
                                )

                            case let .serverSentEvent(sseEvent):
                                messageCount += 1
                                let bytes = sseEvent.data.utf8.count
                                messageBytes += bytes
                                self.notifyStreamMessageIfNeeded(
                                    context: context,
                                    metadata: NetworkStreamMessageMetadata(
                                        sequenceNumber: messageCount,
                                        kind: .serverSentEvent,
                                        bytes: bytes
                                    )
                                )

                            case let .closed(code, _):
                                closeCode = code
                            }

                            if let mappedEvent = try mapper.map(event) {
                                continuation.yield(mappedEvent)
                            }
                        }

                        await self.recordCircuitBreakerSuccessIfNeeded(
                            circuitBreakerAdmission,
                            context: context
                        )
                        self.notifyStreamFinishIfNeeded(
                            context: context,
                            error: nil,
                            metadata: NetworkStreamEventMetadata(
                                duration: Date().timeIntervalSince(context.startTime),
                                eventCount: eventCount,
                                messageCount: messageCount,
                                messageBytes: messageBytes,
                                closeCode: closeCode
                            )
                        )
                        continuation.finish()
                    } catch {
                        let mappedError = ErrorMapper.map(
                            error,
                            context: context,
                            retryCount: 0
                        )
                        await self.recordCircuitBreakerFailureIfNeeded(
                            mappedError,
                            admission: circuitBreakerAdmission,
                            context: context
                        )
                        self.notifyStreamFinishIfNeeded(
                            context: context,
                            error: mappedError,
                            metadata: NetworkStreamEventMetadata(
                                duration: Date().timeIntervalSince(context.startTime),
                                eventCount: eventCount,
                                messageCount: messageCount,
                                messageBytes: messageBytes,
                                closeCode: closeCode
                            )
                        )
                        continuation.finish(throwing: mappedError)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                    Task {
                        await connection.close(code: nil, reason: nil)
                    }
                }
            }

            return NetworkStreamSession(
                events: mappedEvents,
                send: { message in
                    try await connection.send(message)
                },
                ping: {
                    try await connection.ping()
                },
                close: { code, reason in
                    await connection.close(code: code, reason: reason)
                }
            )
        } catch {
            let mappedError = ErrorMapper.map(
                error,
                context: context,
                retryCount: 0
            )
            await recordCircuitBreakerFailureIfNeeded(
                mappedError,
                admission: circuitBreakerAdmission,
                context: context
            )
            notifyStreamFinishIfNeeded(
                context: context,
                error: mappedError,
                metadata: NetworkStreamEventMetadata(
                    duration: Date().timeIntervalSince(context.startTime),
                    eventCount: 0,
                    messageCount: 0,
                    messageBytes: 0
                )
            )
            throw mappedError
        }
    }

    private func perform<E: APIEndpoint>(
        endpoint: E,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> (RequestExecutionResult, Int?) {
        let builtRequest = try RequestBuilder.build(
            endpoint: endpoint,
            configuration: configuration
        )
        let requestSize = requestSize(of: builtRequest)
        let result = try await sendWithRetry(
            request: builtRequest,
            context: context,
            progressHandler: progressHandler
        )

        return (result, requestSize)
    }

    private func prepareStreamRequest(
        _ request: TransportRequest,
        kind: NetworkStreamKind
    ) -> TransportRequest {
        var urlRequest = request.urlRequest

        switch kind {
        case .serverSentEvents:
            if urlRequest.value(forHTTPHeaderField: "Accept") == nil {
                urlRequest.setValue(
                    "text/event-stream",
                    forHTTPHeaderField: "Accept"
                )
            }

        case .webSocket:
            break
        }

        return TransportRequest(
            urlRequest: urlRequest,
            task: request.task
        )
    }

    private func failedStream<Event>(
        _ error: Error,
        context: NetworkRequestContext
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ErrorMapper.map(
                error,
                context: context,
                retryCount: 0
            ))
        }
    }

    private func acquireCircuitBreakerAdmissionIfNeeded(
        for context: NetworkRequestContext
    ) async throws -> EndpointFailureTracker.Admission? {
        guard let circuitBreaker = configuration.circuitBreaker,
              let tracker = configuration.endpointFailureTracker else {
            return nil
        }

        let previousState = await tracker.currentState(for: context)
        let admission = try await tracker.acquireAdmission(
            for: context,
            circuitBreaker: circuitBreaker
        )
        let currentState = await tracker.currentState(for: context)
        notifyCircuitBreakerTransitionIfNeeded(
            context: context,
            from: previousState,
            to: currentState
        )
        return admission
    }

    private func recordCircuitBreakerSuccessIfNeeded(
        _ admission: EndpointFailureTracker.Admission?,
        context: NetworkRequestContext
    ) async {
        guard let admission,
              let tracker = configuration.endpointFailureTracker else {
            return
        }

        let previousState = await tracker.currentState(for: context)
        await tracker.recordSuccess(admission)
        let currentState = await tracker.currentState(for: context)
        notifyCircuitBreakerTransitionIfNeeded(
            context: context,
            from: previousState,
            to: currentState
        )
    }

    private func recordCircuitBreakerFailureIfNeeded(
        _ error: Error,
        admission: EndpointFailureTracker.Admission?,
        context: NetworkRequestContext
    ) async {
        guard let admission,
              let circuitBreaker = configuration.circuitBreaker,
              let tracker = configuration.endpointFailureTracker else {
            return
        }

        let previousState = await tracker.currentState(for: context)
        await tracker.recordFailure(
            error,
            admission: admission,
            circuitBreaker: circuitBreaker
        )
        let currentState = await tracker.currentState(for: context)
        notifyCircuitBreakerTransitionIfNeeded(
            context: context,
            from: previousState,
            to: currentState
        )
    }

    private func sendWithRetry(
        request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?,
        allowsCacheRead: Bool = true,
        allowsStaleRevalidation: Bool = true,
        cacheKeyRequest: URLRequest? = nil,
        cachedResponseForRevalidation: TransportResponse? = nil
    ) async throws -> RequestExecutionResult {
        var currentRequest = request
        var retryCount = 0
        let cachePolicy = resolvedCachePolicy(for: context)

        while true {
            let adaptedRequest = try await adapt(currentRequest, context: context)
            let cacheStorageRequest = normalizedCacheRequest(
                cacheKeyRequest ?? adaptedRequest.urlRequest,
                context: context
            )
            let cacheTimeToLive = resolvedCacheTimeToLive(for: context)
            var requestForTransport = adaptedRequest
            try await awaitEligibleNetworkIfNeeded(
                for: requestForTransport,
                context: context
            )

            let cachedResponse = try await cachedResponseIfAvailable(
                for: cacheStorageRequest,
                context: context,
                cachePolicy: cachePolicy
            )
            let cachedPayload = cachedResponse?.response
            let cachedResponseIsFresh = cachedResponse.map {
                isFresh($0, timeToLive: cacheTimeToLive)
            } ?? false
            let canReturnCachedResponse =
                retryCount == 0
                && allowsCacheRead
                && {
                    guard cachedResponse != nil else { return false }
                    switch cachePolicy {
                    case .staleWhileRevalidate:
                        return true
                    case .returnCacheElseLoad, .memoryOnly, .disk:
                        return cachedResponseIsFresh
                    default:
                        return false
                    }
                }()

            if canReturnCachedResponse,
               let cachedPayload {
                if allowsStaleRevalidation,
                   cachePolicy.refreshesInBackgroundWhenCached,
                   cachedResponseIsFresh == false || cacheTimeToLive == nil {
                    scheduleCacheRefresh(
                        request: currentRequest,
                        cachedResponse: cachedPayload,
                        context: context,
                        cacheKeyRequest: cacheStorageRequest
                    )
                }

                return RequestExecutionResult(
                    response: cachedPayload,
                    retryCount: retryCount
                )
            }

            if retryCount == 0,
               let cachedPayload,
               cachePolicy.readsFromCacheStore,
               cachePolicy.writesToCacheStore,
               cachePolicy.refreshesInBackgroundWhenCached == false,
               cachedResponseIsFresh == false {
                requestForTransport = makeConditionalRevalidationRequest(
                    requestForTransport,
                    cachedResponse: cachedPayload
                )
            }

            do {
                let response = try await transport.send(
                    requestForTransport,
                    context: context,
                    progressHandler: progressHandler
                )

                if let revalidatedResponse = revalidatedCachedResponse(
                    from: response,
                    cachedResponse: cachedResponseForRevalidation ?? cachedPayload,
                    cacheKeyRequest: cacheStorageRequest,
                    cachePolicy: cachePolicy
                ) {
                    return RequestExecutionResult(
                        response: revalidatedResponse,
                        retryCount: retryCount
                    )
                }

                let rawRetryDecision = await evaluateRetry(
                    request: adaptedRequest.urlRequest,
                    result: .success(response),
                    retryCount: retryCount,
                    context: context
                )

                let rawRetryError = retryError(from: response)
                let rawRetryApplication = try await apply(
                    rawRetryDecision,
                    to: &currentRequest,
                    context: context,
                    retryNumber: retryCount + 1,
                    error: rawRetryError
                )

                switch rawRetryApplication {
                case .didRetry:
                    retryCount += 1
                    continue
                case .exhausted:
                    throw executionError(
                        NetworkError.retryExhausted(
                            lastError: rawRetryError,
                            retryCount: retryCount
                        ),
                        retryCount: retryCount,
                        response: response,
                        request: adaptedRequest.urlRequest
                    )
                case .noRetry:
                    break
                }

                do {
                    try await finalize(
                        response: response,
                        request: cacheStorageRequest,
                        context: context,
                        cachePolicy: cachePolicy
                    )
                    return RequestExecutionResult(
                        response: response,
                        retryCount: retryCount
                    )
                } catch {
                    let validationRetryDecision = await evaluateRetry(
                        request: adaptedRequest.urlRequest,
                        result: .failure(error),
                        retryCount: retryCount,
                        context: context
                    )

                    let validationRetryApplication = try await apply(
                        validationRetryDecision,
                        to: &currentRequest,
                        context: context,
                        retryNumber: retryCount + 1,
                        error: error
                    )

                    switch validationRetryApplication {
                    case .didRetry:
                        retryCount += 1
                        continue
                    case .exhausted:
                        throw executionError(
                            NetworkError.retryExhausted(
                                lastError: error,
                                retryCount: retryCount
                            ),
                            retryCount: retryCount,
                            response: response,
                            request: adaptedRequest.urlRequest
                        )
                    case .noRetry:
                        throw executionError(
                            error,
                            retryCount: retryCount,
                            response: response,
                            request: adaptedRequest.urlRequest
                        )
                    }
                }
            } catch let executionError as RequestExecutionError {
                throw executionError
            } catch {
                let retryDecision = await evaluateRetry(
                    request: adaptedRequest.urlRequest,
                    result: .failure(error),
                    retryCount: retryCount,
                    context: context
                )

                let retryApplication = try await apply(
                    retryDecision,
                    to: &currentRequest,
                    context: context,
                    retryNumber: retryCount + 1,
                    error: error
                )

                switch retryApplication {
                case .didRetry:
                    retryCount += 1
                    continue
                case .exhausted:
                    throw executionError(
                        NetworkError.retryExhausted(
                            lastError: error,
                            retryCount: retryCount
                        ),
                        retryCount: retryCount,
                        request: adaptedRequest.urlRequest
                    )
                case .noRetry:
                    throw executionError(
                        error,
                        retryCount: retryCount,
                        request: adaptedRequest.urlRequest
                    )
                }
            }
        }
    }

    private func resolvedCachePolicy(
        for context: NetworkRequestContext
    ) -> NetworkCachePolicy {
        context.options.networkCachePolicy ?? configuration.defaultNetworkCachePolicy
    }

    private func resolvedCacheTimeToLive(
        for context: NetworkRequestContext
    ) -> TimeInterval? {
        context.options.cacheTimeToLive ?? configuration.defaultCacheTimeToLive
    }

    private func resolvedCacheKeyStrategy(
        for context: NetworkRequestContext
    ) -> NetworkCacheKeyStrategy {
        context.options.cacheKeyStrategy ?? configuration.defaultCacheKeyStrategy
    }

    private func resolvedReachabilityRequirement(
        for context: NetworkRequestContext
    ) -> NetworkReachabilityRequirement {
        context.options.reachabilityRequirement ?? configuration.reachabilityRequirement
    }

    private func resolvedMaximumUploadSizeOnExpensiveNetwork(
        for context: NetworkRequestContext
    ) -> Int? {
        context.options.maximumUploadSizeOnExpensiveNetwork
            ?? configuration.maximumUploadSizeOnExpensiveNetwork
    }

    private func resolvedMaximumUploadSizeOnConstrainedNetwork(
        for context: NetworkRequestContext
    ) -> Int? {
        context.options.maximumUploadSizeOnConstrainedNetwork
            ?? configuration.maximumUploadSizeOnConstrainedNetwork
    }

    private func normalizedCacheRequest(
        _ request: URLRequest,
        context: NetworkRequestContext
    ) -> URLRequest {
        guard isCacheable(request) else {
            return request
        }

        switch resolvedCacheKeyStrategy(for: context) {
        case .request:
            return request
        case .normalizeQueryItems:
            guard let url = request.url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return request
            }

            components.fragment = nil
            components.queryItems = components.queryItems?.sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }

            guard let normalizedURL = components.url else {
                return request
            }

            var normalizedRequest = request
            normalizedRequest.url = normalizedURL
            return normalizedRequest
        }
    }

    private func isFresh(
        _ cachedResponse: NetworkCachedResponse,
        timeToLive: TimeInterval?
    ) -> Bool {
        guard let timeToLive else {
            return true
        }

        guard timeToLive > 0 else {
            return false
        }

        return Date().timeIntervalSince(cachedResponse.storedAt) <= timeToLive
    }

    private func cachedResponseIfAvailable(
        for request: URLRequest,
        context: NetworkRequestContext,
        cachePolicy: NetworkCachePolicy
    ) async throws -> NetworkCachedResponse? {
        guard shouldReadFromCacheStore(
            request: request,
            cachePolicy: cachePolicy
        ) else {
            return nil
        }

        guard let cachedResponse = configuration.cacheStore?.cachedResponse(for: request) else {
            return nil
        }

        do {
            try await intercept(cachedResponse.response, context: context)
            try validate(cachedResponse.response, context: context)
            try validateBusinessIfNeeded(cachedResponse.response, context: context)
            return cachedResponse
        } catch {
            configuration.cacheStore?.removeCachedResponse(for: request)
            return nil
        }
    }

    private func finalize(
        response: TransportResponse,
        request: URLRequest,
        context: NetworkRequestContext,
        cachePolicy: NetworkCachePolicy
    ) async throws {
        try await intercept(response, context: context)
        try validate(response, context: context)
        try validateBusinessIfNeeded(response, context: context)
        updateCache(
            with: response,
            for: request,
            cachePolicy: cachePolicy
        )
    }

    private func shouldReadFromCacheStore(
        request: URLRequest,
        cachePolicy: NetworkCachePolicy
    ) -> Bool {
        cachePolicy.readsFromCacheStore && isCacheable(request)
    }

    private func updateCache(
        with response: TransportResponse,
        for request: URLRequest,
        cachePolicy: NetworkCachePolicy
    ) {
        guard isCacheable(request) else {
            return
        }

        if cachePolicy.removesCachedResponse {
            configuration.cacheStore?.removeCachedResponse(for: request)
            return
        }

        guard cachePolicy.writesToCacheStore,
              let storagePolicy = cachePolicy.storagePolicy else {
            return
        }

        configuration.cacheStore?.store(
            response,
            for: request,
            storagePolicy: storagePolicy,
            storedAt: Date()
        )
    }

    private func scheduleCacheRefresh(
        request: TransportRequest,
        cachedResponse: TransportResponse,
        context: NetworkRequestContext,
        cacheKeyRequest: URLRequest
    ) {
        let refreshRequest = makeConditionalRevalidationRequest(
            request,
            cachedResponse: cachedResponse
        )

        Task { [weak self] in
            guard let self else { return }

            _ = try? await self.sendWithRetry(
                request: refreshRequest,
                context: context,
                progressHandler: nil,
                allowsCacheRead: false,
                allowsStaleRevalidation: false,
                cacheKeyRequest: cacheKeyRequest,
                cachedResponseForRevalidation: cachedResponse
            )
        }
    }

    private func makeConditionalRevalidationRequest(
        _ request: TransportRequest,
        cachedResponse: TransportResponse
    ) -> TransportRequest {
        var urlRequest = request.urlRequest

        if urlRequest.value(forHTTPHeaderField: "If-None-Match") == nil,
           let eTag = headerValue(
            named: "ETag",
            in: cachedResponse.response
           ) {
            urlRequest.setValue(
                eTag,
                forHTTPHeaderField: "If-None-Match"
            )
        }

        if urlRequest.value(forHTTPHeaderField: "If-Modified-Since") == nil,
           let lastModified = headerValue(
            named: "Last-Modified",
            in: cachedResponse.response
           ) {
            urlRequest.setValue(
                lastModified,
                forHTTPHeaderField: "If-Modified-Since"
            )
        }

        return TransportRequest(
            urlRequest: urlRequest,
            task: request.task
        )
    }

    private func revalidatedCachedResponse(
        from response: TransportResponse,
        cachedResponse: TransportResponse?,
        cacheKeyRequest: URLRequest,
        cachePolicy: NetworkCachePolicy
    ) -> TransportResponse? {
        guard response.response.statusCode == 304,
              let cachedResponse,
              let responseURL = cacheKeyRequest.url
                ?? cachedResponse.request.url
                ?? response.request.url else {
            return nil
        }

        let mergedHeaders = mergeHeaders(
            existing: headers(from: cachedResponse.response),
            overriding: headers(from: response.response)
        )

        guard let mergedHTTPResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: cachedResponse.response.statusCode,
            httpVersion: nil,
            headerFields: mergedHeaders
        ) else {
            return cachedResponse
        }

        let revalidatedResponse = TransportResponse(
            request: cacheKeyRequest,
            response: mergedHTTPResponse,
            data: cachedResponse.data
        )
        updateCache(
            with: revalidatedResponse,
            for: cacheKeyRequest,
            cachePolicy: cachePolicy
        )
        return revalidatedResponse
    }

    private func awaitEligibleNetworkIfNeeded(
        for request: TransportRequest,
        context: NetworkRequestContext
    ) async throws {
        guard let reachabilityMonitor = configuration.reachabilityMonitor else {
            return
        }

        let reachabilityRequirement = resolvedReachabilityRequirement(for: context)
        let currentStatus = await reachabilityMonitor.currentPathStatus()

        if reachabilityRequirement.isSatisfied(by: currentStatus) {
            try validateExpensiveNetworkUploadIfNeeded(
                request,
                pathStatus: currentStatus,
                context: context
            )
            return
        }

        switch configuration.unsatisfiedPathBehavior {
        case .failFast:
            throw NetworkError.networkAccessRestricted(
                reachabilityRequirement.restrictionReason(
                    for: currentStatus
                )
            )

        case .waitForConnectivity(let timeout):
            guard let satisfiedStatus = await reachabilityMonitor.waitUntilSatisfied(
                reachabilityRequirement,
                timeout: timeout
            ) else {
                let latestStatus = await reachabilityMonitor.currentPathStatus()
                throw NetworkError.networkAccessRestricted(
                    reachabilityRequirement.restrictionReason(
                        for: latestStatus
                    )
                )
            }

            try validateExpensiveNetworkUploadIfNeeded(
                request,
                pathStatus: satisfiedStatus,
                context: context
            )
        }
    }

    private func makeReconnectControllerIfNeeded(
        for kind: NetworkStreamKind,
        context: NetworkRequestContext
    ) -> (any NetworkStreamReconnectControlling)? {
        guard context.options.streamReconnectPolicy != nil else {
            return nil
        }

        switch kind {
        case .serverSentEvents, .webSocket:
            break
        }

        return DefaultNetworkStreamReconnectController(
            reachabilityMonitor: configuration.reachabilityMonitor,
            reachabilityRequirement: resolvedReachabilityRequirement(for: context),
            circuitBreaker: configuration.circuitBreaker,
            endpointFailureTracker: configuration.endpointFailureTracker,
            context: context,
            transitionHandler: { [weak self] metadata in
                guard let self else { return }
                Task {
                    await self.notifyCircuitBreakerTransitionIfNeeded(
                        context: context,
                        metadata: metadata
                    )
                }
            }
        )
    }

    private func validateExpensiveNetworkUploadIfNeeded(
        _ request: TransportRequest,
        pathStatus: NetworkPathStatus,
        context: NetworkRequestContext
    ) throws {
        guard let uploadSize = uploadSize(of: request) else {
            return
        }

        if pathStatus.isExpensive,
           let maximumUploadSize = resolvedMaximumUploadSizeOnExpensiveNetwork(
            for: context
           ),
           uploadSize > maximumUploadSize {
            throw NetworkError.networkAccessRestricted(
                .expensiveUploadTooLarge(
                    maxBytes: maximumUploadSize,
                    actualBytes: uploadSize
                )
            )
        }

        if pathStatus.isConstrained,
           let maximumUploadSize = resolvedMaximumUploadSizeOnConstrainedNetwork(
            for: context
           ),
           uploadSize > maximumUploadSize {
            throw NetworkError.networkAccessRestricted(
                .constrainedUploadTooLarge(
                    maxBytes: maximumUploadSize,
                    actualBytes: uploadSize
                )
            )
        }
    }

    private func uploadSize(of request: TransportRequest) -> Int? {
        switch request.task {
        case .upload(let data):
            return data.count
        case .request, .download, .backgroundDownload:
            return nil
        }
    }

    private func isCacheable(_ request: URLRequest) -> Bool {
        request.httpMethod?.uppercased() == HTTPMethod.get.rawValue
    }

    private func makeContext<E: APIEndpoint>(for endpoint: E) -> NetworkRequestContext {
        NetworkRequestContext(
            environmentName: configuration.environment.name,
            path: endpoint.path,
            method: endpoint.method,
            expectsEmptyResponseBody: E.Response.self == EmptyResponse.self,
            acceptableContentTypes: endpoint.acceptableContentTypes,
            authorization: endpoint.authorization,
            options: endpoint.options,
            allowsOfflineRecoveryRetry: configuration.reachabilityMonitor != nil
                && configuration.unsatisfiedPathBehavior.waitsForConnectivity
        )
    }

    private func makeContext<E: StreamingEndpoint>(
        for endpoint: E
    ) -> NetworkRequestContext {
        NetworkRequestContext(
            environmentName: configuration.environment.name,
            path: endpoint.path,
            method: endpoint.method,
            acceptableContentTypes: [],
            authorization: endpoint.authorization,
            options: endpoint.options,
            allowsOfflineRecoveryRetry: false
        )
    }

    private func adapt(
        _ request: TransportRequest,
        context: NetworkRequestContext
    ) async throws -> TransportRequest {
        var urlRequest = request.urlRequest

        for interceptor in configuration.requestInterceptors {
            urlRequest = try await interceptor.adapt(urlRequest, context: context)
        }

        return TransportRequest(urlRequest: urlRequest, task: request.task)
    }

    private func intercept(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) async throws {
        for interceptor in configuration.responseInterceptors {
            try await interceptor.didReceive(response, context: context)
        }
    }

    private func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        for validator in configuration.responseValidators {
            try validator.validate(response, context: context)
        }
    }

    private func validateBusinessIfNeeded(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        guard response.data.isEmpty == false else { return }
        try configuration.businessValidator?.validate(
            data: response.data,
            response: response.response,
            context: context
        )
    }

    private func evaluateRetry(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision {
        for policy in configuration.retryPolicies {
            let decision = await policy.evaluate(
                request: request,
                result: result,
                retryCount: retryCount,
                context: context
            )

            switch decision {
            case .doNotRetry:
                continue
            case .retry, .retryWith, .retryExhausted:
                return decision
            }
        }

        return .doNotRetry
    }

    private func apply(
        _ decision: RetryDecision,
        to request: inout TransportRequest,
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error
    ) async throws -> RetryApplicationResult {
        switch decision {
        case .doNotRetry:
            return .noRetry

        case let .retry(after):
            notifyRetryIfNeeded(
                context: context,
                retryNumber: retryNumber,
                error: error,
                delay: after
            )
            try await sleep(after)
            return .didRetry

        case let .retryWith(newRequest, after):
            request = TransportRequest(urlRequest: newRequest, task: request.task)
            notifyRetryIfNeeded(
                context: context,
                retryNumber: retryNumber,
                error: error,
                delay: after
            )
            try await sleep(after)
            return .didRetry

        case .retryExhausted:
            return .exhausted
        }
    }

    private func sleep(_ duration: TimeInterval?) async throws {
        guard let duration, duration > 0 else { return }
        let nanoseconds = UInt64(duration * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func notifyStartIfNeeded(_ context: NetworkRequestContext) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.requestDidStart(context)
        }
    }

    private func notifyRetryIfNeeded(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.requestWillRetry(
                context: context,
                retryNumber: retryNumber,
                error: error,
                delay: delay
            )
        }
    }

    private func notifyFinishIfNeeded(_ event: NetworkEvent) {
        let context = context(from: event)
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.requestDidFinish(event)
        }
    }

    private func notifyDecodingDegradedIfNeeded(
        context: NetworkRequestContext,
        warningCount: Int
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.requestDidDegradeDecoding(
                context: context,
                warningCount: warningCount
            )
        }
    }

    private func notifyStreamOpenIfNeeded(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.streamDidOpen(
                context: context,
                metadata: metadata
            )
        }
    }

    private func notifyStreamFinishIfNeeded(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.streamDidFinish(
                context: context,
                error: error,
                metadata: metadata
            )
        }
    }

    private func notifyStreamMessageIfNeeded(
        context: NetworkRequestContext,
        metadata: NetworkStreamMessageMetadata
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.streamDidReceiveMessage(
                context: context,
                metadata: metadata
            )
        }
    }

    private func notifyCircuitBreakerTransitionIfNeeded(
        context: NetworkRequestContext,
        from previousState: CircuitBreakerState,
        to currentState: CircuitBreakerState
    ) {
        guard let metadata = circuitBreakerTransitionMetadata(
            from: previousState,
            to: currentState
        ) else {
            return
        }

        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.circuitBreakerDidTransition(
                context: context,
                metadata: metadata
            )
        }
    }

    private func notifyCircuitBreakerTransitionIfNeeded(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    ) {
        configuration.observers.forEach { observer in
            guard shouldDeliver(observer, for: context) else { return }
            observer.circuitBreakerDidTransition(
                context: context,
                metadata: metadata
            )
        }
    }

    private func context(from event: NetworkEvent) -> NetworkRequestContext {
        switch event {
        case let .success(context, _, _, _):
            return context
        case let .failure(context, _, _, _):
            return context
        }
    }

    private func circuitBreakerTransitionMetadata(
        from previousState: CircuitBreakerState,
        to currentState: CircuitBreakerState
    ) -> CircuitBreakerTransitionMetadata? {
        let previousPhase = circuitBreakerPhase(previousState)
        let currentPhase = circuitBreakerPhase(currentState)

        guard previousPhase != currentPhase else {
            return nil
        }

        let trigger: CircuitBreakerTransitionTrigger

        switch (previousPhase, currentPhase) {
        case (.closed, .open):
            trigger = .failureThresholdReached
        case (.open, .halfOpen):
            trigger = .recoveryProbeStarted
        case (.halfOpen, .closed):
            trigger = .recoveryProbeSucceeded
        case (.halfOpen, .open):
            trigger = .recoveryProbeFailed
        default:
            return nil
        }

        return CircuitBreakerTransitionMetadata(
            fromState: previousPhase,
            toState: currentPhase,
            trigger: trigger
        )
    }

    private func circuitBreakerPhase(
        _ state: CircuitBreakerState
    ) -> CircuitBreakerStatePhase {
        switch state {
        case .closed:
            return .closed
        case .open:
            return .open
        case .halfOpen:
            return .halfOpen
        }
    }

    private func requestSize(of request: TransportRequest) -> Int? {
        switch request.task {
        case .upload(let data):
            return data.count
        default:
            return request.urlRequest.httpBody?.count
        }
    }

    private func responseSize(of response: TransportResponse) -> Int? {
        if let downloadedFileURL = response.downloadedFileURL {
            let values = try? downloadedFileURL.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize
        }

        return response.data.count
    }

    private func retryError(from response: TransportResponse) -> Error {
        let statusCode = response.response.statusCode

        if statusCode == 401 {
            return NetworkError.unauthorized
        }

        return NetworkError.httpStatus(code: statusCode, data: response.data)
    }

    private func executionError(
        _ error: Error,
        retryCount: Int,
        response: TransportResponse? = nil,
        request: URLRequest? = nil
    ) -> RequestExecutionError {
        RequestExecutionError(
            underlying: error,
            retryCount: retryCount,
            statusCode: response?.response.statusCode,
            responseHeaders: response.map(headers(from:)),
            request: request
        )
    }

    private func headers(from response: TransportResponse) -> [String: String] {
        headers(from: response.response)
    }

    private func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { partialResult, item in
            guard let key = item.key as? String else { return }
            partialResult[key] = String(describing: item.value)
        }
    }

    private func headerValue(
        named name: String,
        in response: HTTPURLResponse
    ) -> String? {
        headers(from: response).first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private func mergeHeaders(
        existing: [String: String],
        overriding: [String: String]
    ) -> [String: String] {
        var merged = existing

        for (key, value) in overriding {
            if let existingKey = merged.keys.first(where: {
                $0.caseInsensitiveCompare(key) == .orderedSame
            }) {
                merged.removeValue(forKey: existingKey)
            }

            merged[key] = value
        }

        return merged
    }

    private func request(from error: Error) -> URLRequest? {
        (error as? RequestExecutionError)?.request
    }

    private func shouldDeliver(
        _ observer: any NetworkObserver,
        for context: NetworkRequestContext
    ) -> Bool {
        switch observer.delivery {
        case .always:
            return true
        case .verbose:
            return context.options.allowsLogging
        }
    }

    private func makeFailure(
        from error: Error,
        context: NetworkRequestContext,
        requestSize: Int?,
        executionResult: RequestExecutionResult?
    ) -> (
        failure: NetworkFailure,
        error: NetworkError,
        metadata: NetworkEventMetadata
    ) {
        let executionError = error as? RequestExecutionError
        let retryCount = executionError?.retryCount ?? executionResult?.retryCount ?? 0
        let response = executionResult?.response
        let duration = Date().timeIntervalSince(context.startTime)
        let networkFailure = ErrorMapper.map(
            executionError?.underlying ?? error,
            context: context,
            retryCount: retryCount,
            statusCode: executionError?.statusCode ?? response?.response.statusCode,
            responseHeaders: executionError?.responseHeaders ?? response.map(headers(from:)),
            duration: duration
        )

        return (
            failure: networkFailure,
            error: networkFailure.error,
            metadata: NetworkEventMetadata(
                duration: duration,
                retryCount: retryCount,
                requestSize: requestSize,
                responseSize: response.flatMap(responseSize(of:))
            )
        )
    }
}
