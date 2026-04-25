import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreValidationTests: XCTestCase {
    func testHTTPStatusCodeValidatorRejectsUnauthorizedStatus() throws {
        let response = try makeTransportResponse(
            path: "auth",
            statusCode: 401,
            data: Data()
        )

        do {
            try HTTPStatusCodeValidator().validate(
                response,
                context: makeValidationContext(path: "auth")
            )
            XCTFail("Expected unauthorized")
        } catch {
            guard case .unauthorized = error as? NetworkError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testHTTPStatusCodeValidatorRejectsUnexpectedStatusCode() throws {
        let response = try makeTransportResponse(
            path: "status",
            statusCode: 503,
            data: Data("temporarily unavailable".utf8)
        )

        do {
            try HTTPStatusCodeValidator().validate(
                response,
                context: makeValidationContext(path: "status")
            )
            XCTFail("Expected status code failure")
        } catch {
            guard case let .httpStatus(code, data) = error as? NetworkError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(code, 503)
            XCTAssertEqual(data, Data("temporarily unavailable".utf8))
        }
    }

    func testEmptyDataValidatorAllowsExpectedEmptyResponseBody() async throws {
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data())
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        let responseBody: NetworkCore.EmptyResponse = try await client.request(MockEmptyEndpoint())
        _ = responseBody
    }

    func testEmptyDataValidatorRejectsUnexpectedEmptyResponseBody() async {
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data())
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected empty data failure")
        } catch let failure as NetworkFailure {
            guard case .emptyData = failure.error else {
                return XCTFail("Unexpected failure: \(failure)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testContentTypeValidatorAllowsJSONResponseWithCharset() throws {
        let response = try makeTransportResponse(
            path: "content-type/json",
            statusCode: 200,
            data: Data(#"{"id":1,"name":"bolt"}"#.utf8),
            headers: [
                "Content-Type": "application/json; charset=utf-8"
            ]
        )

        XCTAssertNoThrow(
            try ContentTypeValidator().validate(
                response,
                context: makeValidationContext(path: "content-type/json")
            )
        )
    }

    func testContentTypeValidatorRejectsUnexpectedContentType() throws {
        let response = try makeTransportResponse(
            path: "content-type/html",
            statusCode: 200,
            data: Data("<html></html>".utf8),
            headers: [
                "Content-Type": "text/html"
            ]
        )

        do {
            try ContentTypeValidator().validate(
                response,
                context: makeValidationContext(path: "content-type/html")
            )
            XCTFail("Expected content type failure")
        } catch {
            guard case let .unacceptableContentType(contentType) = error as? NetworkError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(contentType, "text/html")
        }
    }

    func testContentTypeValidatorSkipsDownloadResponses() throws {
        let response = TransportResponse(
            request: URLRequest(url: URL(string: "https://example.com/download")!),
            response: try makeResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"]
            ),
            data: Data(),
            downloadedFileURL: URL(fileURLWithPath: "/tmp/bolt-download.bin")
        )

        XCTAssertNoThrow(
            try ContentTypeValidator().validate(
                response,
                context: makeValidationContext(path: "download")
            )
        )
    }

    func testDefaultConfigurationRejectsUnexpectedEmptyBodyBeforeDecoding() async {
        let transport = SequenceTransport(steps: [
            .success(statusCode: 200, data: Data())
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected empty data failure")
        } catch let failure as NetworkFailure {
            guard case .emptyData = failure.error else {
                return XCTFail("Unexpected failure: \(failure)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultConfigurationRejectsUnexpectedContentTypeBeforeDecoding() async {
        let transport = SequenceTransport(steps: [
            .success(
                statusCode: 200,
                data: Data(#"{"id":1,"name":"bolt"}"#.utf8),
                headers: [
                    "Content-Type": "text/plain"
                ]
            )
        ])

        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )

        do {
            let _: MockModel = try await client.request(MockJSONEndpoint())
            XCTFail("Expected content type failure")
        } catch let failure as NetworkFailure {
            guard case let .unacceptableContentType(contentType) = failure.error else {
                return XCTFail("Unexpected failure: \(failure)")
            }

            XCTAssertEqual(contentType, "text/plain")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnvelopeBusinessValidatorRejectsBusinessFailure() throws {
        let data = Data(
            #"{"code":5001,"message":"boom","requestId":"req-1","traceId":"trace-1","data":{}}"#.utf8
        )

        do {
            try EnvelopeBusinessValidator<APIResponseEnvelope<AnyCodable>>().validate(
                data: data,
                response: try makeResponse(statusCode: 200),
                context: makeValidationContext(path: "business")
            )
            XCTFail("Expected business failure")
        } catch {
            guard case let .business(code, message, errorData) = error as? NetworkError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(code, 5001)
            XCTAssertEqual(message, "boom")
            XCTAssertEqual(errorData, data)
        }
    }

    func testEnvelopeBusinessValidatorRejectsUnauthorizedBusinessCode() throws {
        let data = Data(
            #"{"code":401,"message":"expired","requestId":"req-2","traceId":"trace-2","data":{}}"#.utf8
        )

        do {
            try EnvelopeBusinessValidator<APIResponseEnvelope<AnyCodable>>().validate(
                data: data,
                response: try makeResponse(statusCode: 200),
                context: makeValidationContext(path: "business/unauthorized")
            )
            XCTFail("Expected unauthorized business failure")
        } catch {
            guard case .unauthorized = error as? NetworkError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private func makeValidationContext(
    path: String,
    method: NetworkCore.HTTPMethod = .get,
    expectsEmptyResponseBody: Bool = false,
    acceptableContentTypes: [String] = ["application/json"]
) -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: path,
        method: method,
        expectsEmptyResponseBody: expectsEmptyResponseBody,
        acceptableContentTypes: acceptableContentTypes,
        authorization: .none,
        options: .default
    )
}

private func makeResponse(
    statusCode: Int,
    headers: [String: String]? = nil
) throws -> HTTPURLResponse {
    try XCTUnwrap(
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )
    )
}
