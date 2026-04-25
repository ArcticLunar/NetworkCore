import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreRetryTests: XCTestCase {
    func testIdempotentGetTimeoutRetriesUntilSuccess() async throws {
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
                )]
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let sendCount = await transport.sendCount()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(sendCount, 2)
    }

    func testNonIdempotentPostDoesNotRetryByDefault() async {
        let transport = SequenceTransport(steps: [
            .failure(.timeout)
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [DefaultRetryPolicy(
                    maxRetries: 2,
                    baseDelay: 0,
                    maxDelay: 0,
                    jitterRatio: 0
                )]
            ),
            transport: transport
        )

        do {
            let _: NetworkCore.EmptyResponse = try await client.request(MockEmptyEndpoint())
            XCTFail("Expected timeout")
        } catch let failure as NetworkFailure {
            guard case .timeout = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sendCount = await transport.sendCount()
        XCTAssertEqual(sendCount, 1)
    }

    func testDefaultRetryPolicyPrefersRetryAfterHeader() async throws {
        let request = URLRequest(url: URL(string: "https://example.com/retry")!)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "120"]
            )
        )

        let decision = await DefaultRetryPolicy(
            maxRetries: 2,
            baseDelay: 0.5,
            maxDelay: 1,
            jitterRatio: 0
        ).evaluate(
            request: request,
            result: .success(
                TransportResponse(
                    request: request,
                    response: response,
                    data: Data()
                )
            ),
            retryCount: 0,
            context: NetworkRequestContext(
                environmentName: "test",
                path: "retry",
                method: .get,
                authorization: .none,
                options: RequestOptions(isIdempotent: true)
            )
        )

        guard case .retry(let delay) = decision else {
            return XCTFail("Expected retry decision")
        }

        XCTAssertEqual(delay, 120)
    }

    func testRetryExhaustedReportsRetryCountAndTotalRequests() async {
        let transport = SequenceTransport(steps: [
            .failure(.timeout),
            .failure(.timeout)
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [DefaultRetryPolicy(
                    maxRetries: 1,
                    baseDelay: 0,
                    maxDelay: 0,
                    jitterRatio: 0
                )]
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected retry exhausted")
        } catch let failure as NetworkFailure {
            guard case let .retryExhausted(lastError, retryCount) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(retryCount, 1)
            XCTAssertEqual(failure.context.retryCount, 1)

            guard case .timeout = ErrorMapper.map(lastError) else {
                return XCTFail("Unexpected last error: \(lastError)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sendCount = await transport.sendCount()
        XCTAssertEqual(sendCount, 2)
    }

    func testRetryableHTTPStatusRetriesBeforeValidation() async throws {
        let transport = SequenceTransport(steps: [
            .success(statusCode: 503, data: Data()),
            .success(statusCode: 200, data: Data(#"{"id":1,"name":"bolt"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: [DefaultRetryPolicy(
                    maxRetries: 1,
                    baseDelay: 0,
                    maxDelay: 0,
                    jitterRatio: 0
                )]
            ),
            transport: transport
        )

        let model = try await client.request(MockJSONEndpoint())
        let sendCount = await transport.sendCount()

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
        XCTAssertEqual(sendCount, 2)
    }
}
