import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreCircuitBreakerTests: XCTestCase {
    func testConsecutiveFailuresTripCircuitAndFailFast() async {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 2,
            openDuration: 1
        )
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .failure(.timeout),
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"unused"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                circuitBreaker: breaker,
                endpointFailureTracker: tracker
            ),
            transport: transport
        )
        let endpoint = PathMockJSONEndpoint(path: "unstable")

        await assertRequestFails(
            client: client,
            endpoint: endpoint,
            expectedError: .timeout
        )
        await assertRequestFails(
            client: client,
            endpoint: endpoint,
            expectedError: .timeout
        )

        do {
            let _: MockModel = try await client.request(endpoint)
            XCTFail("Expected circuit to be open")
        } catch let failure as NetworkFailure {
            guard case let .circuitOpen(retryAfter) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertNotNil(retryAfter)
            XCTAssertGreaterThan(retryAfter ?? 0, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sendCount = await transport.sendCount()
        let state = await tracker.currentState(
            for: makeCircuitContext(path: endpoint.path)
        )

        XCTAssertEqual(sendCount, 2)

        guard case .open = state else {
            return XCTFail("Expected circuit to be open")
        }
    }

    func testHalfOpenSuccessClosesCircuit() async throws {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 0.05
        )
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .success(statusCode: 200, data: Data(#"{"id":2,"name":"recovered"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                circuitBreaker: breaker,
                endpointFailureTracker: tracker
            ),
            transport: transport
        )
        let endpoint = PathMockJSONEndpoint(path: "recoverable")

        await assertRequestFails(
            client: client,
            endpoint: endpoint,
            expectedError: .timeout
        )
        await assertCircuitOpen(client: client, endpoint: endpoint)

        try await Task.sleep(nanoseconds: 80_000_000)

        let model = try await client.request(endpoint)
        let sendCount = await transport.sendCount()
        let state = await tracker.currentState(
            for: makeCircuitContext(path: endpoint.path)
        )

        XCTAssertEqual(model, MockModel(id: 2, name: "recovered"))
        XCTAssertEqual(sendCount, 2)
        XCTAssertEqual(state, .closed(consecutiveFailures: 0))
    }

    func testHalfOpenFailureReopensCircuit() async throws {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 0.05
        )
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .failure(.timeout)
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                circuitBreaker: breaker,
                endpointFailureTracker: tracker
            ),
            transport: transport
        )
        let endpoint = PathMockJSONEndpoint(path: "flapping")

        await assertRequestFails(
            client: client,
            endpoint: endpoint,
            expectedError: .timeout
        )

        try await Task.sleep(nanoseconds: 80_000_000)

        await assertRequestFails(
            client: client,
            endpoint: endpoint,
            expectedError: .timeout
        )
        await assertCircuitOpen(client: client, endpoint: endpoint)

        let sendCount = await transport.sendCount()
        let state = await tracker.currentState(
            for: makeCircuitContext(path: endpoint.path)
        )

        XCTAssertEqual(sendCount, 2)

        guard case .open = state else {
            return XCTFail("Expected circuit to be re-opened")
        }
    }

    func testCircuitBreakerIsIsolatedPerEndpoint() async throws {
        let tracker = EndpointFailureTracker()
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            openDuration: 1
        )
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .success(statusCode: 200, data: Data(#"{"id":3,"name":"healthy"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                circuitBreaker: breaker,
                endpointFailureTracker: tracker
            ),
            transport: transport
        )
        let failingEndpoint = PathMockJSONEndpoint(path: "service-a")
        let healthyEndpoint = PathMockJSONEndpoint(path: "service-b")

        await assertRequestFails(
            client: client,
            endpoint: failingEndpoint,
            expectedError: .timeout
        )

        let healthyResponse = try await client.request(healthyEndpoint)

        await assertCircuitOpen(
            client: client,
            endpoint: failingEndpoint
        )

        let failingState = await tracker.currentState(
            for: makeCircuitContext(path: failingEndpoint.path)
        )
        let healthyState = await tracker.currentState(
            for: makeCircuitContext(path: healthyEndpoint.path)
        )
        let sendCount = await transport.sendCount()

        XCTAssertEqual(healthyResponse, MockModel(id: 3, name: "healthy"))
        XCTAssertEqual(sendCount, 2)

        guard case .open = failingState else {
            return XCTFail("Expected failing endpoint circuit to be open")
        }

        XCTAssertEqual(healthyState, .closed(consecutiveFailures: 0))
    }
}

private struct PathMockJSONEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path: String
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
}

private func makeCircuitContext(path: String) -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: path,
        method: .get,
        authorization: .inheritGlobal,
        options: RequestOptions(isIdempotent: true)
    )
}

private func assertRequestFails(
    client: NetworkClient,
    endpoint: PathMockJSONEndpoint,
    expectedError: NetworkError
) async {
    do {
        let _: MockModel = try await client.request(endpoint)
        XCTFail("Expected request to fail")
    } catch let failure as NetworkFailure {
        XCTAssertEqual(mappedComparableError(failure.error), mappedComparableError(expectedError))
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}

private func assertCircuitOpen(
    client: NetworkClient,
    endpoint: PathMockJSONEndpoint
) async {
    do {
        let _: MockModel = try await client.request(endpoint)
        XCTFail("Expected circuit to be open")
    } catch let failure as NetworkFailure {
        guard case let .circuitOpen(retryAfter) = failure.error else {
            return XCTFail("Unexpected error: \(failure)")
        }

        XCTAssertNotNil(retryAfter)
        XCTAssertGreaterThan(retryAfter ?? 0, 0)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}

private func mappedComparableError(_ error: NetworkError) -> String {
    switch error {
    case .timeout:
        return "timeout"
    case .circuitOpen:
        return "circuitOpen"
    default:
        return String(describing: error)
    }
}
