import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreAuthTests: XCTestCase {
    func testValidTokenDoesNotRefreshWhenNotExpiringSoon() async throws {
        let expirationDate = Date().addingTimeInterval(300)
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "stable-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: expirationDate
        )
        let refresher = MockTokenRefresher(
            result: .success(
                AuthTokens(
                    accessToken: "fresh-token",
                    refreshToken: "refresh-token",
                    accessTokenExpiresAt: Date().addingTimeInterval(600)
                )
            )
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher,
            refreshLeadTime: 60
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                requestInterceptors: [
                    AuthInterceptor(
                        credentialsStore: credentialsStore,
                        refreshCoordinator: refreshCoordinator
                    )
                ],
                retryPolicies: []
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let refreshCount = await refresher.refreshCount()
        let requests = await transport.capturedRequests()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer stable-token"
        )
    }

    func testExpiringTokenRefreshesBeforeRequest() async throws {
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "expiring-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: Date().addingTimeInterval(10)
        )
        let refresher = MockTokenRefresher(
            result: .success(
                AuthTokens(
                    accessToken: "fresh-token",
                    refreshToken: "refresh-token",
                    accessTokenExpiresAt: Date().addingTimeInterval(600)
                )
            )
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher,
            refreshLeadTime: 60
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                requestInterceptors: [
                    AuthInterceptor(
                        credentialsStore: credentialsStore,
                        refreshCoordinator: refreshCoordinator
                    )
                ],
                retryPolicies: []
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let refreshCount = await refresher.refreshCount()
        let requests = await transport.capturedRequests()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-token"
        )
    }

    func testConcurrentAccessSharesSingleRefreshTask() async throws {
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "expiring-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: Date().addingTimeInterval(5)
        )
        let refresher = MockTokenRefresher(
            result: .success(
                AuthTokens(
                    accessToken: "fresh-token",
                    refreshToken: "refresh-token",
                    accessTokenExpiresAt: Date().addingTimeInterval(600)
                )
            ),
            delay: 0.05
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher,
            refreshLeadTime: 60
        )

        async let token1 = refreshCoordinator.validAccessToken()
        async let token2 = refreshCoordinator.validAccessToken()

        let resolvedToken1 = try await token1
        let resolvedToken2 = try await token2
        let refreshCount = await refresher.refreshCount()

        XCTAssertEqual(resolvedToken1, "fresh-token")
        XCTAssertEqual(resolvedToken2, "fresh-token")
        XCTAssertEqual(refreshCount, 1)
    }

    func testRefreshFailureKeepsStoredTokensForTransientError() async {
        let expirationDate = Date().addingTimeInterval(-60)
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: expirationDate
        )
        let refresher = MockTokenRefresher(
            result: .failure(NetworkError.timeout)
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher,
            refreshLeadTime: 60
        )

        do {
            _ = try await refreshCoordinator.refreshToken(force: true)
            XCTFail("Expected refresh failure")
        } catch {
            guard case .timeout = ErrorMapper.map(error) else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let storedTokens = try? await credentialsStore.tokens()
        XCTAssertEqual(
            storedTokens ?? nil,
            AuthTokens(
                accessToken: "expired-token",
                refreshToken: "refresh-token",
                accessTokenExpiresAt: expirationDate
            )
        )
    }

    func testRefreshFailureClearsStoredTokensForUnauthorizedError() async {
        let expirationDate = Date().addingTimeInterval(-60)
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: expirationDate
        )
        let refresher = MockTokenRefresher(
            result: .failure(NetworkError.unauthorized)
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher,
            refreshLeadTime: 60
        )

        do {
            _ = try await refreshCoordinator.refreshToken(force: true)
            XCTFail("Expected refresh failure")
        } catch {
            guard case .unauthorized = ErrorMapper.map(error) else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let storedTokens = try? await credentialsStore.tokens()
        XCTAssertNil(storedTokens ?? nil)
    }

    func testRefreshRetryReappliesAuthInterceptor() async throws {
        let credentialsStore = InMemoryAuthCredentialsStore(
            accessToken: "stale-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: Date().addingTimeInterval(600)
        )
        let refresher = MockTokenRefresher(
            result: .success(
                AuthTokens(
                    accessToken: "fresh-token",
                    refreshToken: "refresh-token",
                    accessTokenExpiresAt: Date().addingTimeInterval(600)
                )
            )
        )
        let refreshCoordinator = AuthRefreshCoordinator(
            credentialsStore: credentialsStore,
            refresher: refresher
        )
        let transport = SequenceTransport(steps: [
            .success(statusCode: 401, data: Data()),
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                requestInterceptors: [
                    AuthInterceptor(
                        credentialsStore: credentialsStore,
                        refreshCoordinator: refreshCoordinator
                    )
                ],
                retryPolicies: [
                    UnauthorizedPolicy(
                        defaultStrategy: .refreshAndRetry(maxRetryCount: 1),
                        coordinator: UnauthorizedCoordinator(handler: NoopUnauthorizedHandler()),
                        refreshCoordinator: refreshCoordinator
                    )
                ]
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let refreshCount = await refresher.refreshCount()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(refreshCount, 1)

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer stale-token"
        )
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-token"
        )
    }
}

private actor InMemoryAuthCredentialsStore: AuthCredentialsStore {
    private var storedTokens: AuthTokens?

    init(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        accessTokenExpiresAt: Date? = nil
    ) {
        if let accessToken {
            storedTokens = AuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                accessTokenExpiresAt: accessTokenExpiresAt
            )
        }
    }

    func tokens() async throws -> AuthTokens? {
        storedTokens
    }

    func save(tokens: AuthTokens) async {
        storedTokens = tokens
    }

    func clear() async {
        storedTokens = nil
    }
}

private actor MockTokenRefresher: TokenRefresher {
    private let result: Result<AuthTokens, Error>
    private let delay: TimeInterval
    private var refreshCountValue = 0

    init(
        result: Result<AuthTokens, Error>,
        delay: TimeInterval = 0
    ) {
        self.result = result
        self.delay = delay
    }

    func refreshTokens(using refreshToken: String) async throws -> AuthTokens {
        refreshCountValue += 1
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try result.get()
    }

    func refreshCount() -> Int {
        refreshCountValue
    }
}
