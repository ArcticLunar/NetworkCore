import Foundation
import XCTest
@testable import NetworkCore

struct MockModel: Codable, Equatable {
    let id: Int
    let name: String
}

struct MockJSONEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "model"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
}

struct MockEmptyEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "empty"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .plain
}

struct MockFormEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "submit"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .formURLEncoded([
        "name": "a&b",
        "value": "c=d +/"
    ])
}

func makeConfiguration(
    requestInterceptors: [any RequestInterceptor] = [],
    responseInterceptors: [any ResponseInterceptor] = [],
    responseValidators: [any ResponseValidator]? = nil,
    businessValidator: (any BusinessResponseValidator)? = nil,
    serverErrorDecoder: ServerErrorDecoder = ServerErrorDecoder(),
    requestEncoder: any RequestEncoder = JSONRequestEncoder(),
    responseDecoder: any ResponseDecoder = SafeJSONResponseDecoder(),
    defaultDecodingPolicy: NetworkDecodingPolicy = .strict,
    retryPolicies: [any RetryPolicy] = [
        DefaultRetryPolicy()
    ],
    observers: [any NetworkObserver] = [],
    defaultNetworkCachePolicy: NetworkCachePolicy = .useProtocolCachePolicy,
    defaultCacheTimeToLive: TimeInterval? = nil,
    defaultCacheKeyStrategy: NetworkCacheKeyStrategy = .normalizeQueryItems,
    cacheStore: (any NetworkCacheStore)? = nil,
    reachabilityMonitor: (any NetworkReachabilityMonitor)? = nil,
    reachabilityRequirement: NetworkReachabilityRequirement = .any,
    unsatisfiedPathBehavior: ReachabilityUnsatisfiedBehavior = .failFast,
    maximumUploadSizeOnExpensiveNetwork: Int? = nil,
    maximumUploadSizeOnConstrainedNetwork: Int? = nil,
    appLifecycleMonitor: any NetworkAppLifecycleMonitor = AlwaysActiveNetworkAppLifecycleMonitor(),
    circuitBreaker: CircuitBreaker? = nil,
    endpointFailureTracker: EndpointFailureTracker? = nil
) -> NetworkConfiguration {
    NetworkConfiguration(
        environment: NetworkEnvironment(
            name: "test",
            baseURL: URL(string: "https://example.com")!
        ),
        defaultNetworkCachePolicy: defaultNetworkCachePolicy,
        defaultCacheTimeToLive: defaultCacheTimeToLive,
        defaultCacheKeyStrategy: defaultCacheKeyStrategy,
        requestEncoder: requestEncoder,
        requestInterceptors: requestInterceptors,
        responseInterceptors: responseInterceptors,
        responseValidators: responseValidators,
        businessValidator: businessValidator,
        serverErrorDecoder: serverErrorDecoder,
        responseDecoder: responseDecoder,
        defaultDecodingPolicy: defaultDecodingPolicy,
        retryPolicies: retryPolicies,
        observers: observers,
        cacheStore: cacheStore,
        reachabilityMonitor: reachabilityMonitor,
        reachabilityRequirement: reachabilityRequirement,
        unsatisfiedPathBehavior: unsatisfiedPathBehavior,
        maximumUploadSizeOnExpensiveNetwork: maximumUploadSizeOnExpensiveNetwork,
        maximumUploadSizeOnConstrainedNetwork: maximumUploadSizeOnConstrainedNetwork,
        circuitBreaker: circuitBreaker,
        endpointFailureTracker: endpointFailureTracker,
        appLifecycleMonitor: appLifecycleMonitor
    )
}

final class StaticTransport: NetworkTransport {
    private let response: TransportResponse

    init(response: TransportResponse) {
        self.response = response
    }

    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        response
    }
}

actor SequenceTransport: NetworkTransport {
    enum Step: Sendable {
        case success(statusCode: Int, data: Data, headers: [String: String]? = nil)
        case failure(NetworkError)
    }

    private let steps: [Step]
    private var currentIndex = 0
    private var requests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        requests.append(request.urlRequest)

        guard currentIndex < steps.count else {
            throw NetworkError.invalidRequest("Missing mock transport step")
        }

        let step = steps[currentIndex]
        currentIndex += 1

        switch step {
        case let .success(statusCode, data, headers):
            let response = try makeHTTPResponse(
                url: request.urlRequest.url!,
                statusCode: statusCode,
                headers: resolvedHeaders(
                    statusCode: statusCode,
                    data: data,
                    headers: headers
                )
            )
            return TransportResponse(
                request: request.urlRequest,
                response: response,
                data: data
            )

        case let .failure(error):
            throw error
        }
    }

    func sendCount() -> Int {
        requests.count
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }

    private func makeHTTPResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String]?
    ) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        ) else {
            throw NetworkError.invalidRequest("Unable to create mock response")
        }

        return response
    }

    private func resolvedHeaders(
        statusCode: Int,
        data: Data,
        headers: [String: String]?
    ) -> [String: String]? {
        guard (200...299).contains(statusCode), data.isEmpty == false else {
            return headers
        }

        var resolvedHeaders = headers ?? [:]

        if resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) == false {
            resolvedHeaders["Content-Type"] = "application/json"
        }

        return resolvedHeaders
    }
}

func makeTransportResponse(
    path: String = "model",
    method: String = "GET",
    statusCode: Int,
    data: Data,
    headers: [String: String]? = nil
) throws -> TransportResponse {
    let url = URL(string: "https://example.com/\(path)")!
    var request = URLRequest(url: url)
    request.httpMethod = method

    let response = try XCTUnwrap(
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: resolvedResponseHeaders(
                statusCode: statusCode,
                data: data,
                headers: headers
            )
        )
    )

    return TransportResponse(
        request: request,
        response: response,
        data: data
    )
}

private func resolvedResponseHeaders(
    statusCode: Int,
    data: Data,
    headers: [String: String]?
) -> [String: String]? {
    guard (200...299).contains(statusCode), data.isEmpty == false else {
        return headers
    }

    var resolvedHeaders = headers ?? [:]

    if resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) == false {
        resolvedHeaders["Content-Type"] = "application/json"
    }

    return resolvedHeaders
}
