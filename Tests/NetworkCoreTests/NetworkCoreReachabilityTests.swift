import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreReachabilityTests: XCTestCase {
    func testOfflineFailFastPreventsTransportSend() async {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected offline restriction")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(reason, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sendCount = await transport.sendCount()
        XCTAssertEqual(sendCount, 0)
    }

    func testWaitForConnectivityQueuesUntilReachable() async throws {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                unsatisfiedPathBehavior: .waitForConnectivity(timeout: 1)
            ),
            transport: transport
        )

        let requestTask = Task {
            try await client.request(MockJSONEndpoint()) as MockModel
        }

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await monitor.update(
                .satisfied(interfaces: [.wifi])
            )
        }

        let model = try await requestTask.value
        let sendCount = await transport.sendCount()
        let waitCount = await monitor.waitCount()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(waitCount, 1)
    }

    func testOfflineRetryWaitsForNetworkRecovery() async throws {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .satisfied(interfaces: [.wifi])
        )
        let transport = ReachabilityRetryTransport(monitor: monitor)
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [DefaultRetryPolicy(
                    maxRetries: 1,
                    baseDelay: 0,
                    maxDelay: 0,
                    jitterRatio: 0
                )],
                reachabilityMonitor: monitor,
                unsatisfiedPathBehavior: .waitForConnectivity(timeout: 1)
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let sendCount = await transport.sendCount()
        let waitCount = await monitor.waitCount()

        XCTAssertEqual(model, MockModel(id: 2, name: "recovered"))
        XCTAssertEqual(sendCount, 2)
        XCTAssertEqual(waitCount, 1)
    }

    func testConcurrentRequestsResumeTogetherAfterConnectivityRecovery() async throws {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .unsatisfied
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"first"}"#.utf8)),
            .success(statusCode: 200, data: Data(#"{"id":2,"name":"second"}"#.utf8)),
            .success(statusCode: 200, data: Data(#"{"id":3,"name":"third"}"#.utf8))
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                unsatisfiedPathBehavior: .waitForConnectivity(timeout: 1)
            ),
            transport: transport
        )

        let tasks = (0..<3).map { _ in
            Task {
                try await client.request(MockJSONEndpoint())
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let queuedSendCount = await transport.sendCount()
        let waitCountBeforeRecovery = await monitor.waitCount()
        XCTAssertEqual(queuedSendCount, 0)
        XCTAssertEqual(waitCountBeforeRecovery, 3)

        await monitor.update(.satisfied(interfaces: [.wifi]))

        let models = try await tasks.asyncMap { try await $0.value }
        let deliveredIDs = models.map(\.id).sorted()
        let deliveredNames = models.map(\.name).sorted()
        let recoveredSendCount = await transport.sendCount()

        XCTAssertEqual(deliveredIDs, [1, 2, 3])
        XCTAssertEqual(deliveredNames, ["first", "second", "third"])
        XCTAssertEqual(recoveredSendCount, 3)
    }

    func testWifiOnlyRequirementRejectsCellularPath() async {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .satisfied(
                interfaces: [.cellular],
                isExpensive: true
            )
        )
        let transport = SequenceTransport(steps: [])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                reachabilityRequirement: .wifiOnly
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected network restriction")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(reason, .requiresNonCellularConnection)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExpensiveNetworkUploadLimitBlocksLargeUpload() async {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .satisfied(
                interfaces: [.cellular],
                isExpensive: true
            )
        )
        let transport = SequenceTransport(steps: [])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                maximumUploadSizeOnExpensiveNetwork: 1024
            ),
            transport: transport
        )

        do {
            let _: NetworkCore.EmptyResponse = try await client.request(
                MockLargeUploadEndpoint()
            )
            XCTFail("Expected upload restriction")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(
                reason,
                .expensiveUploadTooLarge(maxBytes: 1024, actualBytes: 2048)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sendCount = await transport.sendCount()
        XCTAssertEqual(sendCount, 0)
    }

    func testDefaultRetryPolicyRetriesOfflineOnlyWhenRecoveryIsEnabled() async {
        let request = URLRequest(url: URL(string: "https://example.com/offline")!)
        let disabledContext = NetworkRequestContext(
            environmentName: "test",
            path: "offline",
            method: .get,
            authorization: .none,
            options: RequestOptions(isIdempotent: true)
        )
        let enabledContext = NetworkRequestContext(
            environmentName: "test",
            path: "offline",
            method: .get,
            authorization: .none,
            options: RequestOptions(isIdempotent: true),
            allowsOfflineRecoveryRetry: true
        )
        let policy = DefaultRetryPolicy(
            maxRetries: 1,
            baseDelay: 0,
            maxDelay: 0,
            jitterRatio: 0
        )

        let disabledDecision = await policy.evaluate(
            request: request,
            result: .failure(NetworkError.offline),
            retryCount: 0,
            context: disabledContext
        )
        let enabledDecision = await policy.evaluate(
            request: request,
            result: .failure(NetworkError.offline),
            retryCount: 0,
            context: enabledContext
        )

        guard case .doNotRetry = disabledDecision else {
            return XCTFail("Expected offline retry to be disabled")
        }

        guard case .retry(let delay) = enabledDecision else {
            return XCTFail("Expected retry decision")
        }

        XCTAssertEqual(delay, 0)
    }

    func testEndpointReachabilityRequirementOverridesGlobalPolicy() async {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .satisfied(
                interfaces: [.cellular],
                isExpensive: true
            )
        )
        let transport = SequenceTransport(steps: [])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                reachabilityRequirement: .any
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockWifiOnlyEndpoint())
            XCTFail("Expected endpoint reachability restriction")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(reason, .requiresNonCellularConnection)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEndpointConstrainedUploadLimitOverridesConfiguration() async {
        let monitor = MockNetworkReachabilityMonitor(
            initialStatus: .satisfied(
                interfaces: [.wifi],
                isConstrained: true
            )
        )
        let transport = SequenceTransport(steps: [])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                reachabilityMonitor: monitor,
                maximumUploadSizeOnConstrainedNetwork: 4096
            ),
            transport: transport
        )

        do {
            let _: NetworkCore.EmptyResponse = try await client.request(
                MockConstrainedUploadEndpoint()
            )
            XCTFail("Expected constrained upload restriction")
        } catch let failure as NetworkFailure {
            guard case let .networkAccessRestricted(reason) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(
                reason,
                .constrainedUploadTooLarge(maxBytes: 1024, actualBytes: 2048)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct MockLargeUploadEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "upload"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .upload(
        data: Data(count: 2048),
        contentType: "application/octet-stream"
    )
}

private struct MockWifiOnlyEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "wifi-only"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
    let options = RequestOptions(
        isIdempotent: true,
        reachabilityRequirement: .wifiOnly
    )
}

private struct MockConstrainedUploadEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "upload/constrained"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .upload(
        data: Data(count: 2048),
        contentType: "application/octet-stream"
    )
    let options = RequestOptions(
        maximumUploadSizeOnConstrainedNetwork: 1024
    )
}

private actor MockNetworkReachabilityMonitor: NetworkReachabilityMonitor {
    private struct Waiter {
        let requirement: NetworkReachabilityRequirement
        let continuation: CheckedContinuation<NetworkPathStatus?, Never>
    }

    private var currentStatus: NetworkPathStatus
    private var waiters: [UUID: Waiter] = [:]
    private var waits = 0

    init(initialStatus: NetworkPathStatus) {
        currentStatus = initialStatus
    }

    func currentPathStatus() -> NetworkPathStatus {
        currentStatus
    }

    func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus? {
        waits += 1

        if requirement.isSatisfied(by: currentStatus) {
            return currentStatus
        }

        let identifier = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    waiters[identifier] = Waiter(
                        requirement: requirement,
                        continuation: continuation
                    )

                    guard let timeout, timeout > 0 else {
                        return
                    }

                    Task {
                        try? await Task.sleep(
                            nanoseconds: UInt64(timeout * 1_000_000_000)
                        )
                        await self.resumeWaiterIfNeeded(
                            identifier,
                            returning: nil
                        )
                    }
                }
            },
            onCancel: {
                Task {
                    await self.resumeWaiterIfNeeded(
                        identifier,
                        returning: nil
                    )
                }
            }
        )
    }

    func update(_ status: NetworkPathStatus) {
        currentStatus = status

        let satisfiedIdentifiers = waiters.compactMap { identifier, waiter in
            waiter.requirement.isSatisfied(by: status) ? identifier : nil
        }

        for identifier in satisfiedIdentifiers {
            guard let waiter = waiters.removeValue(forKey: identifier) else {
                continue
            }

            waiter.continuation.resume(returning: status)
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

private actor ReachabilityRetryTransport: NetworkTransport {
    private let monitor: MockNetworkReachabilityMonitor
    private var currentStep = 0

    init(monitor: MockNetworkReachabilityMonitor) {
        self.monitor = monitor
    }

    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        currentStep += 1

        switch currentStep {
        case 1:
            await monitor.update(.unsatisfied)

            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await self.monitor.update(
                    .satisfied(interfaces: [.wifi])
                )
            }

            throw NetworkError.offline

        case 2:
            return try makeTransportResponse(
                path: "model",
                statusCode: 200,
                data: Data(#"{"id":2,"name":"recovered"}"#.utf8)
            )

        default:
            throw NetworkError.invalidRequest("Unexpected retry transport step")
        }
    }

    func sendCount() -> Int {
        currentStep
    }
}

private extension Array {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)

        for element in self {
            results.append(try await transform(element))
        }

        return results
    }
}
