// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreSafeDecodingTests: XCTestCase {
    func testStrictDecodingFailsForDirtyPayload() async {
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(dirtyPayload.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                defaultDecodingPolicy: .strict
            ),
            transport: transport
        )

        do {
            let _: StrictDecodingModel = try await client.request(
                StrictDecodingEndpoint()
            )
            XCTFail("Expected strict decoding to fail")
        } catch let error as NetworkFailure {
            guard case .decoding = error.error else {
                return XCTFail("Expected decoding failure")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSafeDecodingRecoversDirtyPayloadAndEmitsObservability() async throws {
        let metricsSink = SafeDecodingRecordingMetricsSink()
        let logSink = SafeDecodingRecordingLogSink()
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(dirtyPayload.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                defaultDecodingPolicy: .safe,
                observers: [
                    NetworkLogger(sink: logSink),
                    NetworkMetricsObserver(sink: metricsSink)
                ]
            ),
            transport: transport
        )

        let response: SafeDecodingModel = try await client.request(
            SafeDecodingEndpoint()
        )

        XCTAssertEqual(response.id.value, 42)
        XCTAssertEqual(response.name, "")
        XCTAssertEqual(response.tags.elements, ["alpha", "omega"])
        XCTAssertEqual(
            response.featureFlags.values,
            [
                "enabled": StringBackedBool(true),
                "disabled": StringBackedBool(false)
            ]
        )

        let degradedCounters = metricsSink.counter(
            named: "network.decode_degraded.count"
        )
        XCTAssertEqual(degradedCounters.count, 1)
        XCTAssertEqual(
            degradedCounters.first?.dimensions["warning_count"].flatMap(Int.init).map { $0 > 0 },
            true
        )

        let degradedLog = logSink.records.first {
            $0.phase == .decodeDegraded
        }
        XCTAssertEqual(
            degradedLog?.attributes?["warning_count"].flatMap(Int.init).map { $0 > 0 },
            true
        )
    }

    func testEndpointCanOverrideConfigurationWithSafeDecoding() async throws {
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(dirtyPayload.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                defaultDecodingPolicy: .strict
            ),
            transport: transport
        )

        let response: SafeDecodingModel = try await client.request(
            EndpointSafeDecodingOverrideEndpoint()
        )

        XCTAssertEqual(response.id.value, 42)
        XCTAssertEqual(response.tags.elements, ["alpha", "omega"])
    }

    private var dirtyPayload: String {
        """
        {
          "id": "42",
          "tags": ["alpha", 1, "omega", true],
          "featureFlags": {
            "enabled": "true",
            "disabled": "no",
            "broken": 1
          }
        }
        """
    }
}

private struct StrictDecodingEndpoint: APIEndpoint {
    typealias Response = StrictDecodingModel

    let path = "safe-decoding"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
}

private struct StrictDecodingModel: Decodable, Equatable {
    let id: Int
    let name: String
    let tags: [String]
    let featureFlags: [String: Bool]
}

private struct EndpointSafeDecodingOverrideEndpoint: APIEndpoint {
    typealias Response = SafeDecodingModel

    let path = "safe-decoding"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
    let decodingPolicy: NetworkDecodingPolicy? = .safe
}

private struct SafeDecodingEndpoint: APIEndpoint {
    typealias Response = SafeDecodingModel

    let path = "safe-decoding"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
}

private struct SafeDecodingModel: Decodable, Equatable {
    let id: StringBackedInt
    @Defaulted<EmptyStringDefaultProvider> var name: String
    let tags: LossyArray<String>
    let featureFlags: LossyDictionary<StringBackedBool>
}

private enum EmptyStringDefaultProvider: SafeDecodingDefaultValueProvider {
    static let defaultValue = ""
}

private final class SafeDecodingRecordingLogSink: NetworkLogSink {
    private(set) var records: [NetworkLogRecord] = []

    func log(_ record: NetworkLogRecord) {
        records.append(record)
    }
}

private final class SafeDecodingRecordingMetricsSink: NetworkMetricsSink {
    struct CounterRecord {
        let name: String
        let dimensions: [String: String]
    }

    private let lock = NSLock()
    private var counters: [CounterRecord] = []

    func incrementCounter(_ name: String, dimensions: [String : String]) {
        lock.withLock {
            counters.append(
                CounterRecord(
                    name: name,
                    dimensions: dimensions
                )
            )
        }
    }

    func recordLatency(_ name: String, duration: TimeInterval, dimensions: [String : String]) {}

    func counter(named name: String) -> [CounterRecord] {
        lock.withLock {
            counters.filter { $0.name == name }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
