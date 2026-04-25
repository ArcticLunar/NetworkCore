import Alamofire
import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreSecurityTests: XCTestCase {
    func testSystemDefaultPolicyCreatesDefaultTrustEvaluatorForConfiguredHosts() throws {
        let manager = try XCTUnwrap(
            AlamofireSessionFactory.makeServerTrustManager(
                securityPolicy: .systemDefault(
                    hosts: ["API.EXAMPLE.COM", "api.example.com"],
                    allHostsMustBeEvaluated: true
                )
            )
        )

        XCTAssertEqual(manager.allHostsMustBeEvaluated, true)
        XCTAssertEqual(manager.evaluators.keys.sorted(), ["api.example.com"])

        let evaluator = try XCTUnwrap(
            try manager.serverTrustEvaluator(forHost: "api.example.com")
        )
        XCTAssertTrue(evaluator is DefaultTrustEvaluator)
    }

    func testPinnedCertificatesPolicyCreatesPinnedCertificatesEvaluator() throws {
        let manager = try XCTUnwrap(
            AlamofireSessionFactory.makeServerTrustManager(
                securityPolicy: .pinnedCertificates(
                    hosts: ["secure.example.com"],
                    certificateData: [dummyCertificateData()],
                    allHostsMustBeEvaluated: false
                )
            )
        )

        XCTAssertEqual(manager.allHostsMustBeEvaluated, false)

        let evaluator = try XCTUnwrap(
            try manager.serverTrustEvaluator(forHost: "secure.example.com")
        )
        XCTAssertTrue(evaluator is PinnedCertificatesTrustEvaluator)
    }

    func testPublicKeyPinningPolicyCreatesPublicKeysEvaluator() throws {
        let manager = try XCTUnwrap(
            AlamofireSessionFactory.makeServerTrustManager(
                securityPolicy: .publicKeyPinning(
                    hosts: ["secure.example.com"],
                    certificateData: [dummyCertificateData()]
                )
            )
        )

        let evaluator = try XCTUnwrap(
            try manager.serverTrustEvaluator(forHost: "secure.example.com")
        )
        XCTAssertTrue(evaluator is PublicKeysTrustEvaluator)
    }

    func testDefaultSecurityPolicyDiffersBetweenDebugAndRelease() {
        let baseURL = URL(string: "https://API.EXAMPLE.COM/v1")!

        XCTAssertEqual(
            NetworkDefaults.defaultSecurityPolicy(
                for: baseURL,
                buildConfiguration: .debug
            ),
            .systemDefault(
                hosts: ["api.example.com"],
                allHostsMustBeEvaluated: false
            )
        )

        XCTAssertEqual(
            NetworkDefaults.defaultSecurityPolicy(
                for: baseURL,
                buildConfiguration: .release
            ),
            .systemDefault(
                hosts: ["api.example.com"],
                allHostsMustBeEvaluated: true
            )
        )
    }

    func testMakeSessionAppliesResolvedDefaultSecurityPolicyFromBaseURL() throws {
        let baseURL = URL(string: "https://api.example.com/v1")!
        let session = NetworkDefaults.makeSession(baseURL: baseURL)
        let manager = try XCTUnwrap(session.serverTrustManager)

        XCTAssertEqual(
            manager.allHostsMustBeEvaluated,
            NetworkBuildConfiguration.current == .release
        )

        let evaluator = try XCTUnwrap(
            try manager.serverTrustEvaluator(forHost: "api.example.com")
        )
        XCTAssertTrue(evaluator is DefaultTrustEvaluator)
    }

    func testMakeProductionConfigurationBuildsDefaultObserverStack() {
        let metricsSink = RecordingMetricsSink()
        let customObserver = RecordingObserver()

        let configuration = NetworkDefaults.makeProductionConfiguration(
            environment: NetworkEnvironment(
                name: "prod",
                baseURL: URL(string: "https://api.example.com")!
            ),
            observers: NetworkProductionObservers(
                metricsSink: metricsSink,
                additionalObservers: [customObserver]
            )
        )

        XCTAssertEqual(configuration.observers.count, 3)
        XCTAssertTrue(configuration.observers[0] is NetworkLogger)
        XCTAssertTrue(configuration.observers[1] is NetworkMetricsObserver)
        XCTAssertTrue(configuration.observers[2] is RecordingObserver)
    }

    func testProductionObserversDefaultToReleaseSafeLoggerInReleaseBuildConfiguration() {
        let observers = NetworkProductionObservers(
            buildConfiguration: .release
        )
        let logger = try? XCTUnwrap(observers.logger)

        XCTAssertEqual(logger?.loggingPolicy, .release)
        XCTAssertEqual(observers.metricsDimensionsPolicy, .release)
    }

    func testProductionObserversDefaultToDebugLoggerInDebugBuildConfiguration() {
        let observers = NetworkProductionObservers(
            buildConfiguration: .debug
        )
        let logger = try? XCTUnwrap(observers.logger)

        XCTAssertEqual(logger?.loggingPolicy, .debug)
        XCTAssertEqual(observers.metricsDimensionsPolicy, .debug)
    }

    func testMakeProductionClientUsesConfigurationTimeoutAndResolvedSecurityPolicy() throws {
        let configuration = NetworkDefaults.makeProductionConfiguration(
            environment: NetworkEnvironment(
                name: "prod",
                baseURL: URL(string: "https://api.example.com")!
            ),
            defaultTimeout: 42
        )

        let client = NetworkDefaults.makeProductionClient(
            configuration: configuration
        )

        let session = try XCTUnwrap(
            lookupValue(forKey: "session", in: client) as? Session
        )
        XCTAssertEqual(session.sessionConfiguration.timeoutIntervalForRequest, 42)

        guard let manager = session.serverTrustManager else {
            return XCTFail("Expected session server trust manager")
        }
        XCTAssertEqual(
            manager.allHostsMustBeEvaluated,
            NetworkBuildConfiguration.current == .release
        )
        let evaluator = try manager.serverTrustEvaluator(forHost: "api.example.com")
        XCTAssertTrue(evaluator is DefaultTrustEvaluator)
    }

    func testDefaultBackgroundDownloadSessionIdentifierUsesBundleIdentifierWhenAvailable() {
        XCTAssertEqual(
            NetworkDefaults.defaultBackgroundDownloadSessionIdentifier(
                bundleIdentifier: "com.example.app"
            ),
            "com.example.app.NetworkCoreBackgroundDownload"
        )
    }

    func testDefaultBackgroundDownloadSessionIdentifierFallsBackToLibraryPrefix() {
        XCTAssertEqual(
            NetworkDefaults.defaultBackgroundDownloadSessionIdentifier(
                bundleIdentifier: "   "
            ),
            "NetworkCore.NetworkCoreBackgroundDownload"
        )
    }
}

private func dummyCertificateData() -> Data {
    Data("not-a-real-certificate".utf8)
}

private func lookupValue(forKey key: String, in source: Any) -> Any? {
    let mirror = Mirror(reflecting: source)

    for child in mirror.children {
        if child.label == key {
            return child.value
        }

        if let nestedValue = lookupValue(forKey: key, in: child.value) {
            return nestedValue
        }
    }

    return nil
}

private final class RecordingMetricsSink: NetworkMetricsSink {
    func incrementCounter(
        _ name: String,
        dimensions: [String: String]
    ) {}

    func recordLatency(
        _ name: String,
        duration: TimeInterval,
        dimensions: [String: String]
    ) {}
}

private struct RecordingObserver: NetworkObserver {
    func requestDidStart(_ context: NetworkRequestContext) {}

    func requestDidFinish(_ event: NetworkEvent) {}
}
