import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreObservabilityTests: XCTestCase {
    func testSuccessRequestEmitsStartAndSuccessEvent() async throws {
        let observer = RecordingObserver()
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                observers: [observer]
            ),
            transport: transport
        )

        _ = try await client.request(MockJSONEndpoint())

        let snapshot = observer.snapshot()
        XCTAssertEqual(snapshot.startCount, 1)

        guard let event = snapshot.finishEvent else {
            return XCTFail("Missing finish event")
        }

        switch event {
        case let .success(context, request, response, metadata):
            XCTAssertEqual(context.path, "model")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(response.response.statusCode, 200)
            XCTAssertEqual(metadata.retryCount, 0)
            XCTAssertNotNil(metadata.responseSize)

        case .failure:
            XCTFail("Expected success event")
        }
    }

    func testFailureRequestEmitsStartAndFailureEvent() async {
        let observer = RecordingObserver()
        let transport = SequenceTransport(steps: [
            .failure(.timeout)
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                observers: [observer]
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected request failure")
        } catch {
            let snapshot = observer.snapshot()
            XCTAssertEqual(snapshot.startCount, 1)

            guard let event = snapshot.finishEvent else {
                return XCTFail("Missing finish event")
            }

            switch event {
            case .success:
                XCTFail("Expected failure event")

            case let .failure(context, request, error, metadata):
                XCTAssertEqual(context.path, "model")
                XCTAssertEqual(request?.httpMethod, "GET")
                XCTAssertEqual(metadata.retryCount, 0)

                guard let failure = error as? NetworkFailure else {
                    return XCTFail("Expected network failure")
                }

                guard case .timeout = failure.error else {
                    return XCTFail("Unexpected error: \(failure)")
                }
            }
        }
    }

    func testRetryEventAndFinishMetadataIncludeRetryCount() async throws {
        let observer = RecordingObserver()
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [DefaultRetryPolicy(
                    maxRetries: 1,
                    baseDelay: 0,
                    maxDelay: 0,
                    jitterRatio: 0
                )],
                observers: [observer]
            ),
            transport: transport
        )

        _ = try await client.request(MockJSONEndpoint())

        let snapshot = observer.snapshot()
        XCTAssertEqual(snapshot.startCount, 1)
        XCTAssertEqual(snapshot.retryRecords.count, 1)
        XCTAssertEqual(snapshot.retryRecords.first?.retryNumber, 1)
        XCTAssertEqual(snapshot.retryRecords.first?.delay, 0)

        guard let event = snapshot.finishEvent else {
            return XCTFail("Missing finish event")
        }

        switch event {
        case let .success(_, _, response, metadata):
            XCTAssertEqual(response.response.statusCode, 200)
            XCTAssertEqual(metadata.retryCount, 1)
            XCTAssertNotNil(metadata.responseSize)

        case .failure:
            XCTFail("Expected success event")
        }
    }

    func testNetworkLoggerRedactsAuthorizationAndSensitiveJSONBody() throws {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(
            sink: sink,
            redactor: DefaultNetworkRedactor()
        )
        let context = makeContext(path: "session", method: .post)
        var request = URLRequest(url: URL(string: "https://example.com/session")!)
        request.httpMethod = "POST"
        request.setValue("Bearer super-secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            #"{"access_token":"abc","password":"123","name":"bolt"}"#.utf8
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        let transportResponse = TransportResponse(
            request: request,
            response: response,
            data: Data(#"{"ok":true}"#.utf8)
        )

        logger.requestDidFinish(.success(
            context: context,
            request: request,
            response: transportResponse,
            metadata: NetworkEventMetadata(
                duration: 0.2,
                retryCount: 0,
                requestSize: request.httpBody?.count,
                responseSize: transportResponse.data.count
            )
        ))

        guard let record = sink.records.last else {
            return XCTFail("Missing log record")
        }

        XCTAssertEqual(record.requestHeaders?["Authorization"], "<redacted>")

        let body = try XCTUnwrap(record.requestBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(object["access_token"], "<redacted>")
        XCTAssertEqual(object["password"], "<redacted>")
        XCTAssertEqual(object["name"], "bolt")
    }

    func testReleaseProfileOmitsRequestBodyAndRetainsRedactedFailureResponseBody() throws {
        let sink = RecordingLogSink()
        let profile = NetworkObservabilityProfile.release(
            sink: sink
        )
        let logger = try XCTUnwrap(profile.logger)
        let context = makeContext(path: "session", method: .post)
        var request = URLRequest(url: URL(string: "https://example.com/session")!)
        request.httpMethod = "POST"
        request.setValue("Bearer super-secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            #"{"access_token":"abc","password":"123","name":"bolt"}"#.utf8
        )

        let failure = NetworkFailure(
            error: .serverError(
                statusCode: 500,
                payload: ServerErrorPayload(message: "failed"),
                data: Data(
                    #"{"refresh_token":"secret","message":"failed"}"#.utf8
                )
            ),
            context: NetworkErrorContext(
                requestID: context.requestID,
                environmentName: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: 500,
                duration: 0.2,
                retryCount: 0,
                responseHeaders: ["Content-Type": "application/json"]
            )
        )

        logger.requestDidFinish(.failure(
            context: context,
            request: request,
            error: failure,
            metadata: NetworkEventMetadata(
                duration: 0.2,
                retryCount: 0
            )
        ))

        guard let record = sink.records.last else {
            return XCTFail("Missing log record")
        }

        XCTAssertNil(record.requestBody)

        let responseBody = try XCTUnwrap(record.responseBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseBody) as? [String: String]
        )
        XCTAssertEqual(object["refresh_token"], "<redacted>")
        XCTAssertEqual(object["message"], "failed")
    }

    func testNetworkLoggerTruncatesOversizedRequestBody() throws {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(
            sink: sink,
            policy: NetworkLoggingPolicy(
                requestBodyMode: .redacted,
                responseBodyMode: .redacted,
                maximumBodyBytes: 32
            )
        )
        let context = makeContext(path: "large", method: .post)
        var request = URLRequest(url: URL(string: "https://example.com/large")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            #"{"message":"abcdefghijklmnopqrstuvwxyz0123456789"}"#.utf8
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )

        logger.requestDidFinish(.success(
            context: context,
            request: request,
            response: TransportResponse(
                request: request,
                response: response,
                data: Data(#"{"ok":true}"#.utf8)
            ),
            metadata: NetworkEventMetadata(duration: 0.1, retryCount: 0)
        ))

        guard let body = sink.records.last?.requestBody,
              let rendered = String(data: body, encoding: .utf8) else {
            return XCTFail("Missing truncated body")
        }

        XCTAssertTrue(rendered.contains("<truncated total_bytes="))
    }

    func testNetworkLoggerUsesSafeStructuredErrorSummaryForFailure() throws {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(sink: sink)
        let context = makeContext(path: "session", method: .post)
        let request = URLRequest(url: URL(string: "https://example.com/session?token=secret")!)
        let failure = NetworkFailure(
            error: .serverError(
                statusCode: 500,
                payload: ServerErrorPayload(
                    code: 9001,
                    message: "token=super-secret",
                    requestID: "server-request",
                    traceID: "trace-123"
                ),
                data: Data(#"{"token":"secret"}"#.utf8)
            ),
            context: NetworkErrorContext(
                requestID: context.requestID,
                environmentName: context.environmentName,
                method: context.method,
                path: context.path,
                statusCode: 500,
                duration: 0.2,
                retryCount: 0,
                responseHeaders: ["Content-Type": "application/json"]
            )
        )

        logger.requestDidFinish(.failure(
            context: context,
            request: request,
            error: failure,
            metadata: NetworkEventMetadata(
                duration: 0.2,
                retryCount: 0
            )
        ))

        let record = try XCTUnwrap(sink.records.last)
        let summary = try XCTUnwrap(record.errorDescription)

        XCTAssertTrue(summary.contains("category=server_error"))
        XCTAssertTrue(summary.contains("status_code=500"))
        XCTAssertTrue(summary.contains("server_code=9001"))
        XCTAssertTrue(summary.contains("request_id=\(context.requestID)"))
        XCTAssertTrue(summary.contains("server_request_id=server-request"))
        XCTAssertTrue(summary.contains("trace_id=trace-123"))
        XCTAssertFalse(summary.contains("super-secret"))
        XCTAssertFalse(summary.contains("token=secret"))
    }

    func testEndpointCanDisableHeaderAndBodyLogging() throws {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(sink: sink)
        let context = makeContext(
            path: "private",
            method: .post,
            options: RequestOptions(
                allowsHeaderLogging: false,
                allowsBodyLogging: false
            )
        )
        var request = URLRequest(url: URL(string: "https://example.com/private")!)
        request.httpMethod = "POST"
        request.setValue("Bearer super-secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"password":"123"}"#.utf8)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "secret-cookie"
                ]
            )
        )

        logger.requestDidFinish(.success(
            context: context,
            request: request,
            response: TransportResponse(
                request: request,
                response: response,
                data: Data(#"{"ok":true}"#.utf8)
            ),
            metadata: NetworkEventMetadata(duration: 0.1, retryCount: 0)
        ))

        guard let record = sink.records.last else {
            return XCTFail("Missing log record")
        }

        XCTAssertNil(record.requestHeaders)
        XCTAssertNil(record.responseHeaders)
        XCTAssertNil(record.requestBody)
        XCTAssertNil(record.responseBody)
    }

    func testMetricsObserverRecordsStatusDurationAndErrorCategory() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(path: "metrics", method: .get)

        observer.requestDidStart(context)
        observer.requestWillRetry(
            context: context,
            retryNumber: 1,
            error: NetworkError.timeout,
            delay: 0.5
        )
        observer.requestDidFinish(.failure(
            context: context,
            request: nil,
            error: NetworkFailure(
                error: .timeout,
                context: NetworkErrorContext(
                    requestID: context.requestID,
                    environmentName: context.environmentName,
                    method: context.method,
                    path: context.path,
                    statusCode: nil,
                    duration: 0.25,
                    retryCount: 1
                )
            ),
            metadata: NetworkEventMetadata(
                duration: 0.25,
                retryCount: 1
            )
        ))
        observer.requestDidFinish(.failure(
            context: context,
            request: nil,
            error: NetworkFailure(
                error: .decoding(
                    underlying: NetworkError.invalidResponse,
                    data: Data(#"{}"#.utf8)
                ),
                context: NetworkErrorContext(
                    requestID: context.requestID,
                    environmentName: context.environmentName,
                    method: context.method,
                    path: context.path,
                    statusCode: 200,
                    duration: 0.1,
                    retryCount: 0
                )
            ),
            metadata: NetworkEventMetadata(
                duration: 0.1,
                retryCount: 0
            )
        ))
        observer.requestDidFinish(.failure(
            context: context,
            request: nil,
            error: NetworkFailure(
                error: .serverError(
                    statusCode: 401,
                    payload: ServerErrorPayload(message: "unauthorized"),
                    data: Data()
                ),
                context: NetworkErrorContext(
                    requestID: context.requestID,
                    environmentName: context.environmentName,
                    method: context.method,
                    path: context.path,
                    statusCode: 401,
                    duration: 0.1,
                    retryCount: 0
                )
            ),
            metadata: NetworkEventMetadata(
                duration: 0.1,
                retryCount: 0
            )
        ))

        let snapshot = sink.snapshot()

        XCTAssertTrue(snapshot.counter(named: "network.request.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.retry.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.failure.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.timeout.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.decode_failure.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.401.count").isEmpty == false)

        guard let latency = snapshot.latencies.first else {
            return XCTFail("Missing latency metric")
        }

        XCTAssertEqual(latency.name, "network.request.latency")
        XCTAssertEqual(latency.dimensions["environment"], "test")
        XCTAssertEqual(latency.dimensions["method"], "GET")
        XCTAssertEqual(latency.dimensions["path"], "metrics")
        XCTAssertEqual(latency.dimensions["error_category"], "timeout")
    }

    func testMetricsStillEmitWhenVerboseLoggingIsDisabled() async throws {
        let loggingObserver = RecordingObserver()
        let metricsSink = RecordingMetricsSink()
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                observers: [
                    loggingObserver,
                    NetworkMetricsObserver(sink: metricsSink)
                ]
            ),
            transport: transport
        )

        _ = try await client.request(MetricsOnlyJSONEndpoint())

        let loggingSnapshot = loggingObserver.snapshot()
        let metricsSnapshot = metricsSink.snapshot()

        XCTAssertEqual(loggingSnapshot.startCount, 0)
        XCTAssertNil(loggingSnapshot.finishEvent)
        XCTAssertTrue(metricsSnapshot.counter(named: "network.request.count").isEmpty == false)
        XCTAssertTrue(metricsSnapshot.counter(named: "network.success.count").isEmpty == false)
    }

    func testStreamingEmitsOpenAndFinishObserverEvents() async throws {
        let observer = RecordingObserver()
        let streamTransport = ObservabilityStreamTransport(steps: [
            .event(.open(metadata: NetworkStreamMetadata(statusCode: 200))),
            .event(.message(Data(#"{"id":7,"name":"stream"}"#.utf8))),
            .event(.closed(code: 1000, reason: nil))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                observers: [observer]
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        let session = try await client.openStream(ObservabilitySSEEndpoint())
        var iterator = session.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()

        let snapshot = observer.snapshot()
        XCTAssertEqual(snapshot.startCount, 1)
        XCTAssertEqual(snapshot.streamOpenCount, 1)
        XCTAssertEqual(snapshot.streamMessages.count, 1)
        XCTAssertEqual(snapshot.streamMessages.first?.kind, .webSocketMessage)
        XCTAssertEqual(snapshot.streamMessages.first?.sequenceNumber, 1)
        XCTAssertEqual(snapshot.streamMessages.first?.bytes, 24)
        XCTAssertNil(snapshot.finishEvent)
        XCTAssertEqual(snapshot.streamFinishMetadata?.messageCount, 1)
        XCTAssertEqual(snapshot.streamFinishMetadata?.closeCode, 1000)
        XCTAssertNil(snapshot.streamFinishError)
    }

    func testStreamingMetricsObserverRecordsOpenAndFinish() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(path: "events", method: .get)

        observer.streamDidOpen(
            context: context,
            metadata: NetworkStreamMetadata(statusCode: 200)
        )
        observer.streamDidReceiveMessage(
            context: context,
            metadata: NetworkStreamMessageMetadata(
                sequenceNumber: 1,
                kind: .serverSentEvent,
                bytes: 64
            )
        )
        observer.streamDidFinish(
            context: context,
            error: nil,
            metadata: NetworkStreamEventMetadata(
                duration: 1.5,
                eventCount: 3,
                messageCount: 2,
                messageBytes: 128,
                closeCode: 1000
            )
        )

        let snapshot = sink.snapshot()
        XCTAssertTrue(snapshot.counter(named: "network.stream.open.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.stream.success.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.stream.message.received.count").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.stream.message.bytes").isEmpty == false)
        XCTAssertTrue(snapshot.counter(named: "network.stream.message.count").isEmpty == false)
        XCTAssertEqual(snapshot.latencies.last?.name, "network.stream.duration")
    }

    func testStreamingMetricsObserverRecordsReconnectMetadata() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(path: "events", method: .get)

        observer.streamDidOpen(
            context: context,
            metadata: NetworkStreamMetadata(
                statusCode: 200,
                reconnect: NetworkStreamReconnectMetadata(
                    attempt: 2,
                    reason: .abnormalClosure,
                    gateWaitDuration: 0.15,
                    backoffDelay: 0.3
                )
            )
        )

        let snapshot = sink.snapshot()
        let reconnectCounters = snapshot.counter(named: "network.stream.reconnect.count")
        let gateWaitLatency = snapshot.latencies.first(
            where: { $0.name == "network.stream.reconnect.gate_wait" }
        )?.duration
        let backoffLatency = snapshot.latencies.first(
            where: { $0.name == "network.stream.reconnect.backoff_delay" }
        )?.duration
        XCTAssertEqual(reconnectCounters.count, 1)
        XCTAssertEqual(reconnectCounters.first?.dimensions["reconnect_attempt"], "2")
        XCTAssertEqual(reconnectCounters.first?.dimensions["reconnect_reason"], "abnormal_closure")
        XCTAssertEqual(gateWaitLatency ?? -1, 0.15, accuracy: 0.0001)
        XCTAssertEqual(backoffLatency ?? -1, 0.3, accuracy: 0.0001)
    }

    func testNetworkLoggerEmitsDedicatedStreamReconnectRecord() {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(sink: sink)
        let context = makeContext(path: "events", method: .get)

        logger.streamDidOpen(
            context: context,
            metadata: NetworkStreamMetadata(
                statusCode: 200,
                reconnect: NetworkStreamReconnectMetadata(
                    attempt: 1,
                    reason: .serviceRestart,
                    gateWaitDuration: 0.05,
                    backoffDelay: 0.2
                )
            )
        )

        let reconnectRecord = sink.records.first(where: { $0.phase == .streamReconnect })
        XCTAssertEqual(reconnectRecord?.attributes?["reconnect_attempt"], "1")
        XCTAssertEqual(reconnectRecord?.attributes?["reconnect_reason"], "service_restart")
        XCTAssertEqual(reconnectRecord?.attributes?["gate_wait_duration"], "0.05")
        XCTAssertEqual(reconnectRecord?.attributes?["backoff_delay"], "0.2")
        XCTAssertEqual(sink.records.last?.phase, .streamOpen)
    }

    func testMetricsObserverNormalizesDynamicPathSegments() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(
            path: "customers/123/orders/550e8400-e29b-41d4-a716-446655440000",
            method: .get
        )

        observer.requestDidStart(context)

        let snapshot = sink.snapshot()
        guard let counter = snapshot.counter(named: "network.request.count").last else {
            return XCTFail("Missing request count metric")
        }

        XCTAssertEqual(counter.dimensions["path"], "customers/:id/orders/:uuid")
    }

    func testMetricsObserverPrefersExplicitMetricsPathOverride() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(
            path: "customers/123/orders/456",
            metricsPath: "customers/:customer_id/orders/:order_id",
            method: .get
        )

        observer.requestDidStart(context)

        let snapshot = sink.snapshot()
        guard let counter = snapshot.counter(named: "network.request.count").last else {
            return XCTFail("Missing request count metric")
        }

        XCTAssertEqual(
            counter.dimensions["path"],
            "customers/:customer_id/orders/:order_id"
        )
    }

    func testMetricsObserverTruncatesDimensionValuesUsingPolicy() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(
            sink: sink,
            dimensionsPolicy: NetworkMetricsDimensionsPolicy(
                maximumValueLength: 12
            )
        )
        let context = NetworkRequestContext(
            environmentName: "test-environment-long",
            path: "customers/123/orders/456",
            metricsPath: "customers/:customer_identifier/orders/:order_identifier",
            method: .get,
            authorization: .none,
            options: .default
        )

        observer.requestDidStart(context)

        let snapshot = sink.snapshot()
        guard let counter = snapshot.counter(named: "network.request.count").last else {
            return XCTFail("Missing request count metric")
        }

        XCTAssertEqual(counter.dimensions["environment"], "test-environ")
        XCTAssertEqual(counter.dimensions["path"], "customers/:c")
    }

    func testCircuitBreakerTransitionEventsReachObserver() async {
        let observer = RecordingObserver()
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 0.05
        )
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"recovered"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                observers: [observer],
                circuitBreaker: breaker,
                endpointFailureTracker: tracker
            ),
            transport: transport
        )
        let endpoint = ObservabilityJSONEndpoint(path: "breaker/transitions")

        do {
            let _: MockModel = try await client.request(endpoint)
            XCTFail("Expected first request to fail")
        } catch {}

        try? await Task.sleep(nanoseconds: 80_000_000)
        _ = try? await client.request(endpoint)

        let snapshot = observer.snapshot()
        XCTAssertEqual(
            snapshot.circuitBreakerTransitions.map(\.trigger),
            [
                .failureThresholdReached,
                .recoveryProbeStarted,
                .recoveryProbeSucceeded
            ]
        )
    }

    func testCircuitBreakerMetricsObserverRecordsTransition() {
        let sink = RecordingMetricsSink()
        let observer = NetworkMetricsObserver(sink: sink)
        let context = makeContext(path: "breaker/transitions", method: .get)

        observer.circuitBreakerDidTransition(
            context: context,
            metadata: CircuitBreakerTransitionMetadata(
                fromState: .open,
                toState: .halfOpen,
                trigger: .recoveryProbeStarted
            )
        )

        let snapshot = sink.snapshot()
        let counters = snapshot.counter(named: "network.circuit_breaker.transition.count")
        XCTAssertEqual(counters.count, 1)
        XCTAssertEqual(counters.first?.dimensions["from_state"], "open")
        XCTAssertEqual(counters.first?.dimensions["to_state"], "half_open")
        XCTAssertEqual(counters.first?.dimensions["trigger"], "recovery_probe_started")
    }

    func testCircuitBreakerLoggerEmitsTransitionRecord() {
        let sink = RecordingLogSink()
        let logger = NetworkLogger(sink: sink)
        let context = makeContext(path: "breaker/transitions", method: .get)

        logger.circuitBreakerDidTransition(
            context: context,
            metadata: CircuitBreakerTransitionMetadata(
                fromState: .halfOpen,
                toState: .open,
                trigger: .recoveryProbeFailed
            )
        )

        let record = sink.records.last
        XCTAssertEqual(record?.phase, .circuitBreakerTransition)
        XCTAssertEqual(record?.attributes?["from_state"], "half_open")
        XCTAssertEqual(record?.attributes?["to_state"], "open")
        XCTAssertEqual(record?.attributes?["trigger"], "recovery_probe_failed")
    }
}

private final class RecordingObserver: NetworkObserver {
    struct RetryRecord {
        let retryNumber: Int
        let delay: TimeInterval?
        let error: Error?
    }

    struct Snapshot {
        let startCount: Int
        let retryRecords: [RetryRecord]
        let finishEvent: NetworkEvent?
        let circuitBreakerTransitions: [CircuitBreakerTransitionMetadata]
        let streamOpenCount: Int
        let streamOpenMetadata: [NetworkStreamMetadata?]
        let streamMessages: [NetworkStreamMessageMetadata]
        let streamFinishMetadata: NetworkStreamEventMetadata?
        let streamFinishError: Error?
    }

    private let lock = NSLock()
    private var startCount = 0
    private var retryRecords: [RetryRecord] = []
    private var finishEvent: NetworkEvent?
    private var circuitBreakerTransitions: [CircuitBreakerTransitionMetadata] = []
    private var streamOpenCount = 0
    private var streamOpenMetadata: [NetworkStreamMetadata?] = []
    private var streamMessages: [NetworkStreamMessageMetadata] = []
    private var streamFinishMetadata: NetworkStreamEventMetadata?
    private var streamFinishError: Error?

    func requestDidStart(_ context: NetworkRequestContext) {
        lock.withLock {
            startCount += 1
        }
    }

    func requestWillRetry(
        context: NetworkRequestContext,
        retryNumber: Int,
        error: Error?,
        delay: TimeInterval?
    ) {
        lock.withLock {
            retryRecords.append(
                RetryRecord(
                    retryNumber: retryNumber,
                    delay: delay,
                    error: error
                )
            )
        }
    }

    func requestDidFinish(_ event: NetworkEvent) {
        lock.withLock {
            finishEvent = event
        }
    }

    func circuitBreakerDidTransition(
        context: NetworkRequestContext,
        metadata: CircuitBreakerTransitionMetadata
    ) {
        lock.withLock {
            circuitBreakerTransitions.append(metadata)
        }
    }

    func streamDidOpen(
        context: NetworkRequestContext,
        metadata: NetworkStreamMetadata?
    ) {
        lock.withLock {
            streamOpenCount += 1
            streamOpenMetadata.append(metadata)
        }
    }

    func streamDidReceiveMessage(
        context: NetworkRequestContext,
        metadata: NetworkStreamMessageMetadata
    ) {
        lock.withLock {
            streamMessages.append(metadata)
        }
    }

    func streamDidFinish(
        context: NetworkRequestContext,
        error: Error?,
        metadata: NetworkStreamEventMetadata
    ) {
        lock.withLock {
            streamFinishMetadata = metadata
            streamFinishError = error
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                startCount: startCount,
                retryRecords: retryRecords,
                finishEvent: finishEvent,
                circuitBreakerTransitions: circuitBreakerTransitions,
                streamOpenCount: streamOpenCount,
                streamOpenMetadata: streamOpenMetadata,
                streamMessages: streamMessages,
                streamFinishMetadata: streamFinishMetadata,
                streamFinishError: streamFinishError
            )
        }
    }
}

private final class RecordingLogSink: NetworkLogSink {
    private(set) var records: [NetworkLogRecord] = []

    func log(_ record: NetworkLogRecord) {
        records.append(record)
    }
}

private final class RecordingMetricsSink: NetworkMetricsSink {
    struct CounterRecord {
        let name: String
        let dimensions: [String: String]
    }

    struct LatencyRecord {
        let name: String
        let duration: TimeInterval
        let dimensions: [String: String]
    }

    struct Snapshot {
        let counters: [CounterRecord]
        let latencies: [LatencyRecord]

        func counter(named name: String) -> [CounterRecord] {
            counters.filter { $0.name == name }
        }
    }

    private let lock = NSLock()
    private var counters: [CounterRecord] = []
    private var latencies: [LatencyRecord] = []

    func incrementCounter(_ name: String, dimensions: [String: String]) {
        lock.withLock {
            counters.append(
                CounterRecord(
                    name: name,
                    dimensions: dimensions
                )
            )
        }
    }

    func recordLatency(_ name: String, duration: TimeInterval, dimensions: [String: String]) {
        lock.withLock {
            latencies.append(
                LatencyRecord(
                    name: name,
                    duration: duration,
                    dimensions: dimensions
                )
            )
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                counters: counters,
                latencies: latencies
            )
        }
    }
}

private func makeContext(
    path: String,
    metricsPath: String? = nil,
    method: NetworkCore.HTTPMethod,
    options: RequestOptions = .default
) -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: path,
        metricsPath: metricsPath,
        method: method,
        authorization: .none,
        options: options
    )
}

private struct MetricsOnlyJSONEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "model"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
    let options = RequestOptions(
        isIdempotent: true,
        allowsLogging: false
    )
}

private struct ObservabilitySSEEndpoint: StreamingEndpoint {
    typealias Event = MockModel

    let path = "events"
    let streamKind: NetworkStreamKind = .serverSentEvents
}

private struct ObservabilityJSONEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path: String
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
}

private actor ObservabilityStreamTransport: NetworkStreamTransport {
    enum Step: Sendable {
        case event(NetworkStreamEvent)
        case failure(NetworkError)
    }

    private let steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection {
        _ = request
        _ = kind
        _ = context
        _ = reconnectController
        return ObservabilityStreamConnection(steps: steps)
    }
}

private final class ObservabilityStreamConnection: NetworkStreamConnection, @unchecked Sendable {
    let events: AsyncThrowingStream<NetworkStreamEvent, Error>

    init(steps: [ObservabilityStreamTransport.Step]) {
        events = AsyncThrowingStream { continuation in
            for step in steps {
                switch step {
                case let .event(event):
                    continuation.yield(event)
                case let .failure(error):
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
    }

    func send(_ message: NetworkStreamOutboundMessage) async throws {}
    func ping() async throws {}
    func close(code: Int?, reason: Data?) async {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
