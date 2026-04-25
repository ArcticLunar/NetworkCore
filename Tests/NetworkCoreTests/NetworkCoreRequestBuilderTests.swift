import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreRequestBuilderTests: XCTestCase {
    func testQueryTaskAppendsEncodedURLQueryItems() throws {
        let request = try RequestBuilder.build(
            endpoint: QueryEndpoint(),
            configuration: makeConfiguration()
        ).urlRequest

        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.path, "/search/items")
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "q", value: "bolt core"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
    }

    func testJSONBodySetsContentTypeAndEncodesPayload() throws {
        let request = try RequestBuilder.build(
            endpoint: JSONBodyEndpoint(),
            configuration: makeConfiguration()
        ).urlRequest

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(BuilderPayload.self, from: body)

        XCTAssertEqual(payload, BuilderPayload(name: "bolt", count: 2))
    }

    func testJSONBodyUsesConfigurationRequestEncoder() throws {
        let date = Date(timeIntervalSince1970: 1_714_214_800)
        let request = try RequestBuilder.build(
            endpoint: ConfigurableJSONBodyEndpoint(payload: ConfigurablePayload(userID: 42, createdAt: date)),
            configuration: makeConfiguration(
                requestEncoder: makeSnakeCaseISO8601RequestEncoder()
            )
        ).urlRequest

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(payload["user_id"] as? Int, 42)
        XCTAssertEqual(
            payload["created_at"] as? String,
            ISO8601DateFormatter().string(from: date)
        )
    }

    func testEndpointRequestEncoderOverridesConfigurationRequestEncoder() throws {
        let date = Date(timeIntervalSince1970: 1_714_214_800)
        let request = try RequestBuilder.build(
            endpoint: EndpointOverrideJSONBodyEndpoint(payload: ConfigurablePayload(userID: 7, createdAt: date)),
            configuration: makeConfiguration(
                requestEncoder: makeSnakeCaseISO8601RequestEncoder()
            )
        ).urlRequest

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(payload["userID"] as? Int, 7)
        XCTAssertNil(payload["user_id"])
        let createdAt = try XCTUnwrap(payload["createdAt"] as? Double)
        XCTAssertEqual(createdAt, date.timeIntervalSince1970 * 1000, accuracy: 0.001)
    }

    func testFormURLEncodedBodyEscapesReservedCharacters() throws {
        let request = try RequestBuilder.build(
            endpoint: MockFormEndpoint(),
            configuration: makeConfiguration()
        ).urlRequest

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(
            bodyString,
            "name=a%26b&value=c%3Dd+%2B%2F"
        )
    }

    func testMultipartBodyIncludesBoundaryAndPartMetadata() throws {
        let transportRequest = try RequestBuilder.build(
            endpoint: MultipartEndpoint(),
            configuration: makeConfiguration()
        )
        let request = transportRequest.urlRequest

        guard case let .upload(data) = transportRequest.task else {
            return XCTFail("Expected upload task")
        }

        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))

        XCTAssertTrue(contentType.contains("multipart/form-data"))
        XCTAssertTrue(contentType.contains(MultipartFormEncoder.boundary))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"caption\""))
        XCTAssertTrue(body.contains("bolt-upload"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(body.contains("--\(MultipartFormEncoder.boundary)--"))
    }

    func testEndpointHeadersOverrideDefaultHeaders() throws {
        let request = try RequestBuilder.build(
            endpoint: HeaderEndpoint(),
            configuration: NetworkConfiguration(
                environment: NetworkEnvironment(
                    name: "test",
                    baseURL: URL(string: "https://example.com")!
                ),
                defaultHeaders: [
                    "Accept": "application/json",
                    "X-Trace": "default"
                ]
            )
        ).urlRequest

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace"), "default")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Feature"), "request-builder")
    }
}

private struct QueryEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "search/items"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .query([
        URLQueryItem(name: "q", value: "bolt core"),
        URLQueryItem(name: "page", value: "1")
    ])
}

private struct JSONBodyEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "payload"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .jsonBody(
        BuilderPayload(name: "bolt", count: 2)
    )
}

private struct ConfigurableJSONBodyEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let payload: ConfigurablePayload

    let path = "configurable-payload"
    let method: NetworkCore.HTTPMethod = .post

    var task: RequestTask {
        .jsonBody(payload)
    }
}

private struct EndpointOverrideJSONBodyEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let payload: ConfigurablePayload

    let path = "endpoint-override-payload"
    let method: NetworkCore.HTTPMethod = .post
    let requestEncoder: (any RequestEncoder)? = JSONRequestEncoder()

    var task: RequestTask {
        .jsonBody(payload)
    }
}

private struct MultipartEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "upload"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .multipart([
        MultipartFormPart(
            name: "caption",
            data: Data("bolt-upload".utf8)
        ),
        MultipartFormPart(
            name: "file",
            data: Data("image-bytes".utf8),
            filename: "avatar.jpg",
            contentType: "image/jpeg"
        )
    ])
}

private struct HeaderEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "headers"
    let method: NetworkCore.HTTPMethod = .get
    let task: RequestTask = .plain
    let headers: [String: String] = [
        "Accept": "application/xml",
        "X-Feature": "request-builder"
    ]
}

private struct BuilderPayload: Codable, Equatable {
    let name: String
    let count: Int
}

private struct ConfigurablePayload: Codable, Equatable {
    let userID: Int
    let createdAt: Date
}

private func makeSnakeCaseISO8601RequestEncoder() -> JSONRequestEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return JSONRequestEncoder(encoder: encoder)
}
