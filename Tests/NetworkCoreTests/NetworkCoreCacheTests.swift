import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreCacheTests: XCTestCase {
    func testRequestBuilderMapsNetworkCachePolicyToURLRequestCachePolicy() throws {
        let endpoint = CachedEndpoint(policy: .disk)
        let request = try RequestBuilder.build(
            endpoint: endpoint,
            configuration: makeConfiguration()
        )

        XCTAssertEqual(
            request.urlRequest.cachePolicy,
            .returnCacheDataElseLoad
        )
    }

    func testReturnCacheElseLoadReusesCachedResponse() async throws {
        let cacheStore = RecordingCacheStore()
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(#"{"id":1,"name":"cached"}"#.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )
        let endpoint = CachedEndpoint(policy: .returnCacheElseLoad)

        let first: MockModel = try await client.request(endpoint)
        let second: MockModel = try await client.request(endpoint)
        let sendCount = await transport.sendCount()

        XCTAssertEqual(first, MockModel(id: 1, name: "cached"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(cacheStore.storagePolicies, [.allowed])
    }

    func testMemoryOnlyCachesWithInMemoryStoragePolicy() async throws {
        let cacheStore = RecordingCacheStore()
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(#"{"id":2,"name":"memory"}"#.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )

        let first: MockModel = try await client.request(
            CachedEndpoint(policy: .memoryOnly)
        )
        let second: MockModel = try await client.request(
            CachedEndpoint(policy: .memoryOnly)
        )
        let sendCount = await transport.sendCount()

        XCTAssertEqual(first, MockModel(id: 2, name: "memory"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(cacheStore.storagePolicies, [.allowedInMemoryOnly])
    }

    func testNoStoreAlwaysHitsTransport() async throws {
        let cacheStore = RecordingCacheStore()
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(#"{"id":1,"name":"first"}"#.utf8)
            ),
            .success(
                statusCode: 200,
                data: Data(#"{"id":2,"name":"second"}"#.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )
        let endpoint = CachedEndpoint(policy: .noStore)

        let first: MockModel = try await client.request(endpoint)
        let second: MockModel = try await client.request(endpoint)
        let sendCount = await transport.sendCount()

        XCTAssertEqual(first, MockModel(id: 1, name: "first"))
        XCTAssertEqual(second, MockModel(id: 2, name: "second"))
        XCTAssertEqual(sendCount, 2)
        XCTAssertTrue(cacheStore.storagePolicies.isEmpty)
    }

    func testStaleWhileRevalidateRefreshesCacheInBackground() async throws {
        let cacheStore = RecordingCacheStore()
        let refreshExpectation = expectation(description: "background refresh")
        let transport = SignalingTransport(
            steps: [
                .init(
                    statusCode: 200,
                    data: Data(#"{"id":1,"name":"stale"}"#.utf8)
                ),
                .init(
                    statusCode: 200,
                    data: Data(#"{"id":2,"name":"fresh"}"#.utf8)
                )
            ],
            onSecondSend: {
                refreshExpectation.fulfill()
            }
        )
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )
        let endpoint = CachedEndpoint(policy: .staleWhileRevalidate)

        let first: MockModel = try await client.request(endpoint)
        let second: MockModel = try await client.request(endpoint)

        XCTAssertEqual(first, MockModel(id: 1, name: "stale"))
        XCTAssertEqual(second, first)

        await fulfillment(of: [refreshExpectation], timeout: 1)

        let third: MockModel = try await client.request(endpoint)
        XCTAssertEqual(third, MockModel(id: 2, name: "fresh"))
    }

    func testStaleWhileRevalidateUsesConditionalHeadersAndKeepsCacheOn304() async throws {
        let refreshCompletion = expectation(description: "conditional refresh completed")
        refreshCompletion.expectedFulfillmentCount = 2
        let cacheStore = RecordingCacheStore {
            refreshCompletion.fulfill()
        }
        let lastModified = "Wed, 21 Oct 2015 07:28:00 GMT"
        let configuration = makeConfiguration(
            retryPolicies: [],
            cacheStore: cacheStore
        )
        let transport = SignalingTransport(
            steps: [
                .init(
                    statusCode: 200,
                    data: Data(#"{"id":1,"name":"stale"}"#.utf8),
                    headers: [
                        "ETag": "\"cache-v1\"",
                        "Last-Modified": lastModified
                    ]
                ),
                .init(
                    statusCode: 304,
                    data: Data(),
                    headers: [
                        "ETag": "\"cache-v1\"",
                        "Last-Modified": lastModified
                    ]
                )
            ]
        )
        let client = NetworkClient(
            configuration: configuration,
            transport: transport
        )
        let endpoint = CachedEndpoint(policy: .staleWhileRevalidate)

        let first: MockModel = try await client.request(endpoint)
        let second: MockModel = try await client.request(endpoint)

        XCTAssertEqual(first, MockModel(id: 1, name: "stale"))
        XCTAssertEqual(second, first)

        await fulfillment(of: [refreshCompletion], timeout: 1)

        let capturedRequests = await transport.capturedRequests()
        XCTAssertEqual(capturedRequests.count, 2)
        XCTAssertEqual(
            capturedRequests[1].value(forHTTPHeaderField: "If-None-Match"),
            "\"cache-v1\""
        )
        XCTAssertEqual(
            capturedRequests[1].value(forHTTPHeaderField: "If-Modified-Since"),
            lastModified
        )
        XCTAssertEqual(
            cacheStore.storagePoliciesSnapshot(),
            [.allowed, .allowed]
        )

        let request = try RequestBuilder.build(
            endpoint: endpoint,
            configuration: configuration
        ).urlRequest
        let cachedResponse = try XCTUnwrap(
            cacheStore.cachedResponse(for: request)
        )
        let model = try JSONDecoder().decode(MockModel.self, from: cachedResponse.response.data)
        XCTAssertEqual(model, first)
    }

    func testCacheKeyNormalizationReusesCacheAcrossQueryOrdering() async throws {
        let cacheStore = RecordingCacheStore()
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(#"{"id":3,"name":"normalized"}"#.utf8)
            )
        ])
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )

        let first: MockModel = try await client.request(
            CacheQueryEndpoint(queryItems: [
                URLQueryItem(name: "b", value: "2"),
                URLQueryItem(name: "a", value: "1")
            ])
        )
        let second: MockModel = try await client.request(
            CacheQueryEndpoint(queryItems: [
                URLQueryItem(name: "a", value: "1"),
                URLQueryItem(name: "b", value: "2")
            ])
        )
        let sendCount = await transport.sendCount()

        XCTAssertEqual(first, MockModel(id: 3, name: "normalized"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(sendCount, 1)
    }

    func testExpiredTTLUsesConditionalRevalidationAndKeepsCachedBodyOn304() async throws {
        let cacheStore = RecordingCacheStore()
        let transport = SignalingTransport(
            steps: [
                .init(
                    statusCode: 200,
                    data: Data(#"{"id":4,"name":"ttl"}"#.utf8),
                    headers: ["ETag": "\"ttl-v1\""]
                ),
                .init(
                    statusCode: 304,
                    data: Data(),
                    headers: ["ETag": "\"ttl-v1\""]
                )
            ]
        )
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [],
                cacheStore: cacheStore
            ),
            transport: transport
        )
        let endpoint = CachedEndpoint(
            policy: .returnCacheElseLoad,
            cacheTimeToLive: 0
        )

        let first: MockModel = try await client.request(endpoint)
        let second: MockModel = try await client.request(endpoint)
        let requests = await transport.capturedRequests()

        XCTAssertEqual(first, MockModel(id: 4, name: "ttl"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "If-None-Match"),
            "\"ttl-v1\""
        )
    }
}

private struct CachedEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "cache/model"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
    let options: RequestOptions

    init(
        policy: NetworkCachePolicy,
        cacheTimeToLive: TimeInterval? = nil
    ) {
        options = RequestOptions(
            networkCachePolicy: policy,
            cacheTimeToLive: cacheTimeToLive,
            isIdempotent: true
        )
    }
}

private struct CacheQueryEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "cache/query"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask
    let options = RequestOptions(
        networkCachePolicy: .returnCacheElseLoad,
        isIdempotent: true
    )

    init(queryItems: [URLQueryItem]) {
        task = .query(queryItems)
    }
}

private final class RecordingCacheStore: NetworkCacheStore, @unchecked Sendable {
    private let lock = NSLock()
    private let onStore: (@Sendable () -> Void)?
    private var storage: [CacheKey: NetworkCachedResponse] = [:]
    private(set) var storagePolicies: [URLCache.StoragePolicy] = []

    init(onStore: (@Sendable () -> Void)? = nil) {
        self.onStore = onStore
    }

    func cachedResponse(for request: URLRequest) -> NetworkCachedResponse? {
        lock.withLock {
            storage[CacheKey(request: request)]
        }
    }

    func store(
        _ response: TransportResponse,
        for request: URLRequest,
        storagePolicy: URLCache.StoragePolicy,
        storedAt: Date
    ) {
        lock.withLock {
            storage[CacheKey(request: request)] = NetworkCachedResponse(
                response: response,
                storedAt: storedAt
            )
            storagePolicies.append(storagePolicy)
        }
        onStore?()
    }

    func removeCachedResponse(for request: URLRequest) {
        _ = lock.withLock {
            storage.removeValue(forKey: CacheKey(request: request))
        }
    }

    func storagePoliciesSnapshot() -> [URLCache.StoragePolicy] {
        lock.withLock {
            storagePolicies
        }
    }
}

private struct CacheKey: Hashable {
    let url: URL?
    let method: String?

    init(request: URLRequest) {
        url = request.url
        method = request.httpMethod
    }
}

private actor SignalingTransport: NetworkTransport {
    struct Step: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]?

        init(
            statusCode: Int,
            data: Data,
            headers: [String: String]? = nil
        ) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    private let steps: [Step]
    private let onSecondSend: @Sendable () -> Void
    private var currentIndex = 0
    private var requests: [URLRequest] = []

    init(
        steps: [Step],
        onSecondSend: @escaping @Sendable () -> Void = {}
    ) {
        self.steps = steps
        self.onSecondSend = onSecondSend
    }

    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        requests.append(request.urlRequest)

        guard currentIndex < steps.count else {
            throw NetworkError.invalidRequest("Missing signaling transport response")
        }

        let step = steps[currentIndex]
        currentIndex += 1

        if currentIndex == 2 {
            onSecondSend()
        }

        return try makeTransportResponse(
            path: "cache/model",
            statusCode: step.statusCode,
            data: step.data,
            headers: step.headers
        )
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }
}
