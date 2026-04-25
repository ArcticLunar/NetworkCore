import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreErrorMappingTests: XCTestCase {
    func testURLErrorMappingCoversTimeoutCancelledOfflineDnsAndTLS() {
        guard case .timeout = ErrorMapper.map(URLError(.timedOut)) else {
            return XCTFail("Expected timeout")
        }

        guard case .cancelled = ErrorMapper.map(URLError(.cancelled)) else {
            return XCTFail("Expected cancelled")
        }

        guard case .offline = ErrorMapper.map(URLError(.notConnectedToInternet)) else {
            return XCTFail("Expected offline error")
        }

        guard case .dnsFailure = ErrorMapper.map(URLError(.dnsLookupFailed)) else {
            return XCTFail("Expected dns failure")
        }

        guard case .cannotConnect = ErrorMapper.map(URLError(.cannotConnectToHost)) else {
            return XCTFail("Expected cannot connect")
        }

        guard case .tlsFailure = ErrorMapper.map(URLError(.secureConnectionFailed)) else {
            return XCTFail("Expected tls failure")
        }

        guard case .serverTrustFailure = ErrorMapper.map(URLError(.serverCertificateUntrusted)) else {
            return XCTFail("Expected server trust failure")
        }
    }

    func testServerErrorBodyBecomesNetworkFailureWithContext() async {
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 500,
                data: Data(#"{"code":5001,"message":"server exploded","requestId":"req-123"}"#.utf8)
            )
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockNonIdempotentJSONEndpoint())
            XCTFail("Expected server error")
        } catch let failure as NetworkFailure {
            guard case let .serverError(statusCode, payload, _) = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(payload.code, 5001)
            XCTAssertEqual(payload.message, "server exploded")
            XCTAssertEqual(payload.requestID, "req-123")
            XCTAssertEqual(failure.context.statusCode, 500)
            XCTAssertEqual(failure.context.path, "model")
            XCTAssertEqual(failure.context.retryCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDecodingFailureIncludesHTTPContext() async {
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data(#"{"id":"oops"}"#.utf8))
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected decoding failure")
        } catch let failure as NetworkFailure {
            guard case .decoding = failure.error else {
                return XCTFail("Unexpected error: \(failure)")
            }

            XCTAssertEqual(failure.context.statusCode, 200)
            XCTAssertEqual(failure.context.retryCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetryExhaustedFailureRetainsContext() async {
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
            XCTAssertNil(failure.context.statusCode)
            XCTAssertEqual(failure.context.environmentName, "test")

            guard case .timeout = ErrorMapper.map(lastError) else {
                return XCTFail("Unexpected last error: \(lastError)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorDecoderExtractsEnvelopeRequestAndTraceIdentifiers() {
        let data = Data(
            #"{"code":5001,"message":"bad gateway","requestId":"req-321","traceId":"trace-654","data":null}"#.utf8
        )

        let payload = ServerErrorDecoder().decode(from: data)

        XCTAssertEqual(payload?.code, 5001)
        XCTAssertEqual(payload?.message, "bad gateway")
        XCTAssertEqual(payload?.requestID, "req-321")
        XCTAssertEqual(payload?.traceID, "trace-654")
    }
}

private struct MockNonIdempotentJSONEndpoint: APIEndpoint {
    typealias Response = MockModel

    let path = "model"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .plain
}
