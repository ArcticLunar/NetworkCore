// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreStreamingTests: XCTestCase {
    func testSSEStreamDecodesJSONPayloads() async throws {
        let streamTransport = MockNetworkStreamTransport(steps: [
            .event(.open(metadata: NetworkStreamMetadata(statusCode: 200))),
            .event(.serverSentEvent(ServerSentEvent(
                event: "message",
                data: #"{"id":1,"name":"bolt"}"#
            ))),
            .event(.closed(code: nil, reason: nil))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        var iterator = await client.stream(MockSSEEndpoint()).makeAsyncIterator()
        let model = try await iterator.next()
        let end = try await iterator.next()
        let capturedRequest = await streamTransport.lastRequest()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertNil(end)
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Accept"),
            "text/event-stream"
        )
    }

    func testWebSocketStreamUsesWSSSchemeAndSubprotocolHeader() async throws {
        let streamTransport = MockNetworkStreamTransport(steps: [
            .event(.message(Data(#"{"id":2,"name":"socket"}"#.utf8)))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        var iterator = await client.stream(MockWebSocketEndpoint()).makeAsyncIterator()
        let model = try await iterator.next()
        let capturedRequest = await streamTransport.lastRequest()
        let capturedKind = await streamTransport.lastKind()
        let queryItems = URLComponents(
            url: try XCTUnwrap(capturedRequest?.url),
            resolvingAgainstBaseURL: false
        )?.queryItems

        XCTAssertEqual(model, MockModel(id: 2, name: "socket"))
        XCTAssertEqual(capturedKind, .webSocket)
        XCTAssertEqual(capturedRequest?.url?.scheme, "wss")
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"),
            "chat, superchat"
        )
        XCTAssertEqual(
            queryItems,
            [URLQueryItem(name: "room", value: "bolt")]
        )
    }

    func testOpenStreamForWebSocketSupportsSendPingAndClose() async throws {
        let streamTransport = MockNetworkStreamTransport(steps: [
            .event(.open(metadata: nil))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        let session = try await client.openStream(MockWebSocketEndpoint())
        try await session.send(text: "hello")
        try await session.send(data: Data([1, 2, 3]))
        try await session.ping()
        await session.close(code: 1000, reason: Data("bye".utf8))
        let sentMessages = await streamTransport.sentMessages()
        let pingCount = await streamTransport.pingCount()
        let closeCode = await streamTransport.closeCode()

        XCTAssertEqual(sentMessages, [.text("hello"), .data(Data([1, 2, 3]))])
        XCTAssertEqual(pingCount, 1)
        XCTAssertEqual(closeCode, 1000)
    }

    func testSSEClientReconnectsAndPropagatesLastEventID() async throws {
        let loader = MockSSEConnectionLoader(steps: [
            .success(
                lines: [
                    "id: evt-1",
                    "data: {\"id\":1,\"name\":\"first\"}",
                    ""
                ]
            ),
            .success(
                lines: [
                    "data: {\"id\":2,\"name\":\"second\"}",
                    ""
                ]
            )
        ])
        let client = SSEClient(
            loader: loader,
            defaultReconnectDelay: 0,
            maximumReconnectAttempts: 1
        )
        let connection = client.connect(
            URLRequest(url: URL(string: "https://example.com/events")!)
        )

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        let firstEvent = try await iterator.next()
        _ = try await iterator.next()
        let secondEvent = try await iterator.next()
        let first = try XCTUnwrap(firstEvent)
        let second = try XCTUnwrap(secondEvent)
        let requestCount = await loader.requestCount()
        let lastEventIDHeader = await loader.lastEventIDHeader(at: 1)

        XCTAssertEqual(
            first,
            .serverSentEvent(ServerSentEvent(
                id: "evt-1",
                data: #"{"id":1,"name":"first"}"#
            ))
        )
        XCTAssertEqual(
            second,
            .serverSentEvent(ServerSentEvent(
                data: #"{"id":2,"name":"second"}"#
            ))
        )
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(lastEventIDHeader, "evt-1")
    }

    func testSSEReconnectControllerWaitsForReachabilityBeforeRetry() async throws {
        let reachabilityMonitor = TestStreamingReconnectReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let loader = MockSSEConnectionLoader(steps: [
            .success(
                lines: [
                    "id: evt-1",
                    "data: {\"id\":1,\"name\":\"first\"}",
                    ""
                ]
            ),
            .success(
                lines: [
                    "data: {\"id\":2,\"name\":\"reachable\"}",
                    ""
                ]
            )
        ])
        let controller = DefaultNetworkStreamReconnectController(
            reachabilityMonitor: reachabilityMonitor,
            reachabilityRequirement: .any,
            context: makeStreamingCircuitContext(path: "sse/reconnect")
        )
        let connection = SSEClient(
            loader: loader,
            defaultReconnectDelay: 0,
            maximumReconnectAttempts: 1
        ).connect(
            URLRequest(url: URL(string: "https://example.com/events")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            reconnectController: controller
        )

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()

        try await Task.sleep(nanoseconds: 50_000_000)
        let requestCountBeforeRecovery = await loader.requestCount()
        let waitCount = await reachabilityMonitor.waitCount()
        XCTAssertEqual(requestCountBeforeRecovery, 1)
        XCTAssertEqual(waitCount, 1)

        await reachabilityMonitor.update(.satisfied(interfaces: [.wifi]))

        let reopened = try await iterator.next()
        let secondEvent = try await iterator.next()
        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened SSE stream")
        }
        XCTAssertEqual(metadata?.statusCode, 200)
        XCTAssertEqual(metadata?.headers?["Content-Type"], "text/event-stream")
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .networkInterruption)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0.04)
        XCTAssertEqual(metadata?.reconnect?.backoffDelay ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(
            secondEvent,
            .serverSentEvent(ServerSentEvent(
                data: #"{"id":2,"name":"reachable"}"#
            ))
        )
        let requestCountAfterRecovery = await loader.requestCount()
        let replayedLastEventID = await loader.lastEventIDHeader(at: 1)
        XCTAssertEqual(requestCountAfterRecovery, 2)
        XCTAssertEqual(replayedLastEventID, "evt-1")
    }

    func testSSEReconnectControllerRespectsCircuitBreakerOpenDuration() async throws {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 0.05
        )
        let loader = MockSSEConnectionLoader(steps: [
            .success(
                lines: [
                    "data: {\"id\":1,\"name\":\"first\"}",
                    ""
                ]
            ),
            .success(
                lines: [
                    "data: {\"id\":2,\"name\":\"breaker\"}",
                    ""
                ]
            )
        ])
        let context = makeStreamingCircuitContext(path: "sse/reconnect")
        let controller = DefaultNetworkStreamReconnectController(
            circuitBreaker: breaker,
            endpointFailureTracker: tracker,
            context: context,
            circuitOpenPollInterval: 0.01
        )
        let admission = try await tracker.acquireAdmission(
            for: context,
            circuitBreaker: breaker
        )
        await tracker.recordFailure(
            NetworkError.timeout,
            admission: admission,
            circuitBreaker: breaker
        )

        let connection = SSEClient(
            loader: loader,
            defaultReconnectDelay: 0,
            maximumReconnectAttempts: 1
        ).connect(
            URLRequest(url: URL(string: "https://example.com/events")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            reconnectController: controller
        )

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()
        let reopened = try await iterator.next()
        let secondEvent = try await iterator.next()

        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened SSE stream")
        }
        XCTAssertEqual(metadata?.statusCode, 200)
        XCTAssertEqual(metadata?.headers?["Content-Type"], "text/event-stream")
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .networkInterruption)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0.04)
        XCTAssertEqual(metadata?.reconnect?.backoffDelay ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(
            secondEvent,
            .serverSentEvent(ServerSentEvent(
                data: #"{"id":2,"name":"breaker"}"#
            ))
        )

        let firstRecordedRequestDate = await loader.requestDate(at: 0)
        let secondRecordedRequestDate = await loader.requestDate(at: 1)
        let firstRequestDate = try XCTUnwrap(firstRecordedRequestDate)
        let secondRequestDate = try XCTUnwrap(secondRecordedRequestDate)
        XCTAssertGreaterThanOrEqual(
            secondRequestDate.timeIntervalSince(firstRequestDate),
            0.045
        )
    }

    func testStreamingOpenFailureParticipatesInCircuitBreaker() async {
        let streamTransport = FailingOpenStreamTransport()
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                circuitBreaker: CircuitBreaker(
                    failureThreshold: 1,
                    openDuration: 60
                )
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        do {
            let _ = try await client.openStream(MockSSEEndpoint())
            XCTFail("Expected first stream open to fail")
        } catch let failure as NetworkFailure {
            guard case .cannotConnect = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            let _ = try await client.openStream(MockSSEEndpoint())
            XCTFail("Expected circuit open on second attempt")
        } catch let failure as NetworkFailure {
            guard case .circuitOpen = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingRespectsReachabilityGate() async throws {
        let monitor = MockStreamingReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let streamTransport = MockNetworkStreamTransport(steps: [
            .event(.message(Data(#"{"id":3,"name":"offline"}"#.utf8)))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        var iterator = await client.stream(MockSSEEndpoint()).makeAsyncIterator()

        do {
            let _ = try await iterator.next()
            XCTFail("Expected stream to fail before transport starts")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(reason, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let openCount = await streamTransport.openCount()
        XCTAssertEqual(openCount, 0)
    }

    func testStreamingEndpointReachabilityRequirementOverridesGlobalPolicy() async throws {
        let monitor = MockStreamingReachabilityMonitor(
            initialStatus: .satisfied(
                interfaces: [.cellular],
                isExpensive: true
            )
        )
        let streamTransport = MockNetworkStreamTransport(steps: [])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                reachabilityRequirement: .any
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        var iterator = await client.stream(MockWifiOnlySSEEndpoint()).makeAsyncIterator()

        do {
            let _ = try await iterator.next()
            XCTFail("Expected stream to fail before transport starts")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(reason, .requiresNonCellularConnection)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let openCount = await streamTransport.openCount()
        XCTAssertEqual(openCount, 0)
    }

    func testWebSocketReconnectPolicyReconnectsAfterAbnormalClosure() async throws {
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":4,"name":"reconnected"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let streamTransport = DefaultNetworkStreamTransport(
            webSocketClient: WebSocketClient(loader: loader)
        )
        let client = NetworkClient(
            configuration: makeConfiguration(retryPolicies: []),
            transport: SequenceTransport(steps: []),
            streamTransport: streamTransport
        )

        var iterator = await client.stream(MockReconnectWebSocketEndpoint()).makeAsyncIterator()
        let model = try await iterator.next()
        let end = try await iterator.next()
        let requestCount = loader.requestCount()

        XCTAssertEqual(model, MockModel(id: 4, name: "reconnected"))
        XCTAssertNil(end)
        XCTAssertEqual(requestCount, 2)
    }

    func testWebSocketReconnectPolicyDoesNotReconnectAfterNormalClosureByDefault() async throws {
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":5,"name":"once"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let connection = WebSocketClient(loader: loader).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 2,
                backoff: .fixed(delay: 0)
            )
        )

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        let event = try await iterator.next()
        let closed = try await iterator.next()
        let end = try await iterator.next()

        XCTAssertEqual(event, .message(Data(#"{"id":5,"name":"once"}"#.utf8)))
        XCTAssertEqual(closed, .closed(code: 1000, reason: nil))
        XCTAssertNil(end)
        XCTAssertEqual(loader.requestCount(), 1)
    }

    func testWebSocketReconnectWaitsForActiveLifecycleBeforeRetrying() async throws {
        let lifecycleMonitor = TestNetworkAppLifecycleMonitor(
            initialState: .inactive
        )
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":6,"name":"resumed"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let connection = WebSocketClient(
            loader: loader,
            appLifecycleMonitor: lifecycleMonitor
        ).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            )
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(loader.requestCount(), 1)

        await lifecycleMonitor.update(.active)

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()
        let reopened = try await iterator.next()
        let message = try await iterator.next()

        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened WebSocket stream")
        }
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .abnormalClosure)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0.04)
        XCTAssertEqual(metadata?.reconnect?.backoffDelay ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(message, .message(Data(#"{"id":6,"name":"resumed"}"#.utf8)))
        XCTAssertEqual(loader.requestCount(), 2)
    }

    func testNetworkClientOpenStreamWaitsForActiveLifecycleBeforeWebSocketRetry() async throws {
        let lifecycleMonitor = TestNetworkAppLifecycleMonitor(
            initialState: .inactive
        )
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":7,"name":"client-default"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                appLifecycleMonitor: lifecycleMonitor
            ),
            transport: SequenceTransport(steps: []),
            streamTransport: DefaultNetworkStreamTransport(
                webSocketClient: WebSocketClient(
                    loader: loader,
                    appLifecycleMonitor: lifecycleMonitor
                )
            )
        )
        var iterator = await client.stream(MockReconnectWebSocketEndpoint()).makeAsyncIterator()

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(loader.requestCount(), 1)

        await lifecycleMonitor.update(.active)

        let model = try await iterator.next()
        XCTAssertEqual(model, MockModel(id: 7, name: "client-default"))
        XCTAssertEqual(loader.requestCount(), 2)
    }

    func testWebSocketReconnectControllerWaitsForReachabilityBeforeRetry() async throws {
        let reachabilityMonitor = TestStreamingReconnectReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":9,"name":"reachable"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let controller = DefaultNetworkStreamReconnectController(
            reachabilityMonitor: reachabilityMonitor,
            reachabilityRequirement: .any,
            context: makeStreamingCircuitContext(path: "socket/reconnect")
        )
        let connection = WebSocketClient(loader: loader).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            reconnectController: controller
        )
        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()

        try await Task.sleep(nanoseconds: 50_000_000)
        let waitCount = await reachabilityMonitor.waitCount()
        XCTAssertEqual(loader.requestCount(), 1)
        XCTAssertEqual(waitCount, 1)

        await reachabilityMonitor.update(.satisfied(interfaces: [.wifi]))

        let reopened = try await iterator.next()
        let model = try await iterator.next()
        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened WebSocket stream")
        }
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .abnormalClosure)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0.045)
        XCTAssertEqual(metadata?.reconnect?.backoffDelay ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(model, .message(Data(#"{"id":9,"name":"reachable"}"#.utf8)))
        XCTAssertEqual(loader.requestCount(), 2)
    }

    func testWebSocketReconnectRequiresLifecycleAndReachabilityRecovery() async throws {
        let lifecycleMonitor = TestNetworkAppLifecycleMonitor(
            initialState: .inactive
        )
        let reachabilityMonitor = TestStreamingReconnectReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":11,"name":"gated"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let controller = DefaultNetworkStreamReconnectController(
            reachabilityMonitor: reachabilityMonitor,
            reachabilityRequirement: .any,
            context: makeStreamingCircuitContext(path: "socket/reconnect/gated")
        )
        let connection = WebSocketClient(
            loader: loader,
            appLifecycleMonitor: lifecycleMonitor
        ).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            reconnectController: controller
        )
        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()

        try await Task.sleep(nanoseconds: 50_000_000)
        let waitCountBeforeActivation = await reachabilityMonitor.waitCount()
        XCTAssertEqual(loader.requestCount(), 1)
        XCTAssertEqual(waitCountBeforeActivation, 0)

        await lifecycleMonitor.update(.active)

        try await Task.sleep(nanoseconds: 50_000_000)
        let waitCountAfterActivation = await reachabilityMonitor.waitCount()
        XCTAssertEqual(loader.requestCount(), 1)
        XCTAssertEqual(waitCountAfterActivation, 1)

        await reachabilityMonitor.update(.satisfied(interfaces: [.wifi]))

        let reopened = try await iterator.next()
        let message = try await iterator.next()

        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened WebSocket stream")
        }
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .abnormalClosure)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0.09)
        XCTAssertEqual(message, .message(Data(#"{"id":11,"name":"gated"}"#.utf8)))
        XCTAssertEqual(loader.requestCount(), 2)
    }

    func testWebSocketReconnectControllerRespectsCircuitBreakerOpenDuration() async throws {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 0.05
        )
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":10,"name":"breaker"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let context = makeStreamingCircuitContext(path: "socket/reconnect")
        let controller = DefaultNetworkStreamReconnectController(
            circuitBreaker: breaker,
            endpointFailureTracker: tracker,
            context: context,
            circuitOpenPollInterval: 0.01
        )
        let admission = try await tracker.acquireAdmission(
            for: context,
            circuitBreaker: breaker
        )
        await tracker.recordFailure(
            NetworkError.timeout,
            admission: admission,
            circuitBreaker: breaker
        )

        let connection = WebSocketClient(loader: loader).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            reconnectController: controller
        )
        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()
        let reopened = try await iterator.next()
        let model = try await iterator.next()
        let firstRequestDate = try XCTUnwrap(loader.requestDate(at: 0))
        let secondRequestDate = try XCTUnwrap(loader.requestDate(at: 1))

        guard case let .open(metadata) = reopened else {
            return XCTFail("Expected reopened WebSocket stream")
        }
        XCTAssertEqual(metadata?.reconnect?.attempt, 1)
        XCTAssertEqual(metadata?.reconnect?.reason, .abnormalClosure)
        XCTAssertGreaterThanOrEqual(metadata?.reconnect?.gateWaitDuration ?? 0, 0)
        XCTAssertEqual(metadata?.reconnect?.backoffDelay ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(model, .message(Data(#"{"id":10,"name":"breaker"}"#.utf8)))
        XCTAssertGreaterThanOrEqual(
            secondRequestDate.timeIntervalSince(firstRequestDate),
            0.045
        )
    }

    func testReconnectBackoffExponentialDelayCapsAtMaximum() {
        let backoff = NetworkStreamReconnectBackoff.exponential(
            initialDelay: 0.5,
            multiplier: 2,
            maximumDelay: 2
        )

        XCTAssertEqual(backoff.delay(forAttempt: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 3), 2.0, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 4), 2.0, accuracy: 0.0001)
    }

    func testReconnectBackoffAppliesJitterWithinExpectedRange() {
        let backoff = NetworkStreamReconnectBackoff.fixed(
            delay: 10,
            jitterRatio: 0.2
        )

        XCTAssertEqual(
            backoff.delay(forAttempt: 1, randomValue: 0),
            8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            backoff.delay(forAttempt: 1, randomValue: 0.5),
            10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            backoff.delay(forAttempt: 1, randomValue: 1),
            12,
            accuracy: 0.0001
        )
    }

    func testWebSocketReconnectBudgetAddsDelayWhenReconnectsAreTooFrequent() async throws {
        let loader = MockWebSocketTaskLoader(tasks: [
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .close(code: .abnormalClosure)
            ]),
            MockWebSocketTask(steps: [
                .message(.string(#"{"id":8,"name":"budgeted"}"#)),
                .close(code: .normalClosure)
            ])
        ])
        let connection = WebSocketClient(loader: loader).connect(
            URLRequest(url: URL(string: "wss://example.com/socket")!),
            reconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 3,
                backoff: .fixed(delay: 0),
                budget: NetworkStreamReconnectBudget(
                    maximumAttempts: 1,
                    interval: 0.05
                )
            )
        )

        var iterator = connection.events.makeAsyncIterator()
        _ = try await iterator.next()
        _ = try await iterator.next()
        _ = try await iterator.next()
        _ = try await iterator.next()
        _ = try await iterator.next()
        let message = try await iterator.next()

        let firstReconnect = try XCTUnwrap(loader.requestDate(at: 1))
        let secondReconnect = try XCTUnwrap(loader.requestDate(at: 2))

        XCTAssertEqual(
            message,
            .message(Data(#"{"id":8,"name":"budgeted"}"#.utf8))
        )
        XCTAssertGreaterThanOrEqual(
            secondReconnect.timeIntervalSince(firstReconnect),
            0.045
        )
    }
}

private struct MockSSEEndpoint: StreamingEndpoint {
    typealias Event = MockModel

    let path = "events"
    let streamKind: NetworkStreamKind = .serverSentEvents
}

private struct MockWebSocketEndpoint: StreamingEndpoint {
    typealias Event = MockModel

    let path = "socket"
    let task: RequestTask = .webSocket(
        queryItems: [URLQueryItem(name: "room", value: "bolt")],
        subprotocols: ["chat", "superchat"]
    )
    let streamKind: NetworkStreamKind = .webSocket
}

private struct MockWifiOnlySSEEndpoint: StreamingEndpoint {
    typealias Event = MockModel

    let path = "events/wifi-only"
    let streamKind: NetworkStreamKind = .serverSentEvents
    let options = RequestOptions(
        reachabilityRequirement: .wifiOnly
    )
}

private struct MockReconnectWebSocketEndpoint: StreamingEndpoint {
    typealias Event = MockModel

    let path = "socket/reconnect"
    let task: RequestTask = .webSocket(queryItems: [], subprotocols: [])
    let options = RequestOptions(
        streamReconnectPolicy: NetworkStreamReconnectPolicy(
            maximumAttempts: 1,
            backoff: .fixed(delay: 0)
        ),
        isIdempotent: true
    )
    let streamKind: NetworkStreamKind = .webSocket
}

private actor MockNetworkStreamTransport: NetworkStreamTransport {
    enum Step: Sendable {
        case event(NetworkStreamEvent)
        case failure(NetworkError)
    }

    private let steps: [Step]
    private var requests: [URLRequest] = []
    private var kinds: [NetworkStreamKind] = []
    private var sent: [NetworkStreamOutboundMessage] = []
    private var pings = 0
    private var closedCode: Int?

    init(steps: [Step]) {
        self.steps = steps
    }

    nonisolated func openConnection(
        _ request: TransportRequest,
        kind: NetworkStreamKind,
        context: NetworkRequestContext,
        reconnectController: (any NetworkStreamReconnectControlling)?
    ) async throws -> any NetworkStreamConnection {
        _ = reconnectController
        await self.record(
            request: request.urlRequest,
            kind: kind
        )
        return MockStreamConnection(
            transport: self,
            steps: await self.resolvedSteps()
        )
    }

    func openCount() -> Int {
        requests.count
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }

    func lastKind() -> NetworkStreamKind? {
        kinds.last
    }

    func recordSent(_ message: NetworkStreamOutboundMessage) {
        sent.append(message)
    }

    func sentMessages() -> [NetworkStreamOutboundMessage] {
        sent
    }

    func recordPing() {
        pings += 1
    }

    func pingCount() -> Int {
        pings
    }

    func recordClose(code: Int?) {
        closedCode = code
    }

    func closeCode() -> Int? {
        closedCode
    }

    private func record(request: URLRequest, kind: NetworkStreamKind) {
        requests.append(request)
        kinds.append(kind)
    }

    private func resolvedSteps() -> [Step] {
        steps
    }
}

private final class MockStreamConnection: NetworkStreamConnection, @unchecked Sendable {
    let events: AsyncThrowingStream<NetworkStreamEvent, Error>

    private let transport: MockNetworkStreamTransport

    init(
        transport: MockNetworkStreamTransport,
        steps: [MockNetworkStreamTransport.Step]
    ) {
        self.transport = transport
        self.events = AsyncThrowingStream { continuation in
            let task = Task {
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

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func send(_ message: NetworkStreamOutboundMessage) async throws {
        await transport.recordSent(message)
    }

    func ping() async throws {
        await transport.recordPing()
    }

    func close(code: Int?, reason: Data?) async {
        await transport.recordClose(code: code)
    }
}

private actor MockStreamingReachabilityMonitor: NetworkReachabilityMonitor {
    private let status: NetworkPathStatus

    init(initialStatus: NetworkPathStatus) {
        status = initialStatus
    }

    func currentPathStatus() -> NetworkPathStatus {
        status
    }

    func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus? {
        nil
    }
}

private actor TestStreamingReconnectReachabilityMonitor: NetworkReachabilityMonitor {
    private struct Waiter {
        let requirement: NetworkReachabilityRequirement
        let continuation: CheckedContinuation<NetworkPathStatus?, Never>
    }

    private var status: NetworkPathStatus
    private var waits = 0
    private var waiters: [UUID: Waiter] = [:]

    init(initialStatus: NetworkPathStatus) {
        status = initialStatus
    }

    func currentPathStatus() -> NetworkPathStatus {
        status
    }

    func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus? {
        _ = timeout

        if requirement.isSatisfied(by: status) {
            return status
        }

        waits += 1
        let identifier = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[identifier] = Waiter(
                    requirement: requirement,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task {
                await self.resumeWaiterIfNeeded(
                    identifier,
                    returning: nil
                )
            }
        }
    }

    func update(_ status: NetworkPathStatus) {
        self.status = status

        let satisfiedIdentifiers = waiters.compactMap { identifier, waiter in
            waiter.requirement.isSatisfied(by: status) ? identifier : nil
        }

        for identifier in satisfiedIdentifiers {
            resumeWaiterIfNeeded(identifier, returning: status)
        }
    }

    func waitCount() -> Int {
        waits
    }

    private func resumeWaiterIfNeeded(
        _ identifier: UUID,
        returning status: NetworkPathStatus?
    ) {
        guard let waiter = waiters.removeValue(forKey: identifier) else {
            return
        }

        waiter.continuation.resume(returning: status)
    }
}

private actor TestNetworkAppLifecycleMonitor: NetworkAppLifecycleMonitor {
    private var state: NetworkAppLifecycleState
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(initialState: NetworkAppLifecycleState) {
        state = initialState
    }

    func currentState() -> NetworkAppLifecycleState {
        state
    }

    func waitUntilActive() async {
        guard state != .active else {
            return
        }

        let identifier = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[identifier] = continuation
            }
        } onCancel: {
            Task {
                await self.removeWaiter(identifier)
            }
        }
    }

    func update(_ state: NetworkAppLifecycleState) {
        self.state = state

        guard state == .active else {
            return
        }

        let activeWaiters = waiters.values
        waiters.removeAll()

        for waiter in activeWaiters {
            waiter.resume()
        }
    }

    private func removeWaiter(_ identifier: UUID) {
        waiters.removeValue(forKey: identifier)
    }
}

private actor MockSSEConnectionLoader: SSEConnectionLoading {
    struct Step: Sendable {
        let lines: [String]

        static func success(lines: [String]) -> Self {
            Step(lines: lines)
        }
    }

    private let steps: [Step]
    private var requests: [URLRequest] = []
    private var requestDates: [Date] = []
    private var index = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func load(
        request: URLRequest
    ) async throws -> (lines: AsyncThrowingStream<String, Error>, response: URLResponse) {
        requests.append(request)
        requestDates.append(Date())
        let step = steps[index]
        index += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        let lines = AsyncThrowingStream<String, Error> { continuation in
            for line in step.lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (lines, response)
    }

    func requestCount() -> Int {
        requests.count
    }

    func lastEventIDHeader(at index: Int) -> String? {
        requests[index].value(forHTTPHeaderField: "Last-Event-ID")
    }

    func requestDate(at index: Int) -> Date? {
        guard requestDates.indices.contains(index) else {
            return nil
        }

        return requestDates[index]
    }
}

private actor FailingOpenStreamTransport: NetworkStreamTransport {
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
        throw NetworkError.cannotConnect(underlying: URLError(.cannotConnectToHost))
    }
}

private final class MockWebSocketTaskLoader: WebSocketTaskLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [MockWebSocketTask]
    private var requests: [URLRequest] = []
    private var requestDates: [Date] = []

    init(tasks: [MockWebSocketTask]) {
        self.tasks = tasks
    }

    func makeTask(request: URLRequest) -> any WebSocketTasking {
        lock.withLock {
            requests.append(request)
            requestDates.append(Date())
            return tasks.removeFirst()
        }
    }

    func requestCount() -> Int {
        lock.withLock { requests.count }
    }

    func requestDate(at index: Int) -> Date? {
        lock.withLock {
            guard requestDates.indices.contains(index) else {
                return nil
            }

            return requestDates[index]
        }
    }
}

private final class MockWebSocketTask: WebSocketTasking, @unchecked Sendable {
    enum Step: Sendable {
        case message(URLSessionWebSocketTask.Message)
        case close(code: URLSessionWebSocketTask.CloseCode)
    }

    private let lock = NSLock()
    private let steps: [Step]
    private var index = 0
    private(set) var closeCode: URLSessionWebSocketTask.CloseCode = .invalid
    private(set) var closeReason: Data?

    init(steps: [Step]) {
        self.steps = steps
    }

    func resume() {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        let step = lock.withLock { () -> Step? in
            guard index < steps.count else { return nil }
            let step = steps[index]
            index += 1
            return step
        }

        guard let step else {
            throw URLError(.networkConnectionLost)
        }

        switch step {
        case let .message(message):
            return message

        case let .close(code):
            closeCode = code
            throw URLError(.networkConnectionLost)
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {}

    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        pongReceiveHandler(nil)
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.closeCode = closeCode
        self.closeReason = reason
    }
}

private func makeStreamingCircuitContext(path: String) -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: path,
        method: .get,
        authorization: .inheritGlobal,
        options: RequestOptions(
            streamReconnectPolicy: NetworkStreamReconnectPolicy(
                maximumAttempts: 1,
                backoff: .fixed(delay: 0)
            ),
            isIdempotent: true
        )
    )
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
