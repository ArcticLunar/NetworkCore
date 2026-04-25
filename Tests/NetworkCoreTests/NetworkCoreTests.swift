import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreTests: XCTestCase {
    func testDefaultConfigurationDecodesNonEnvelopeJSON() async throws {
        let endpoint = MockJSONEndpoint()
        let transport = StaticTransport(
            response: try makeTransportResponse(
                path: endpoint.path,
                statusCode: 200,
                data: Data(#"{"id":1,"name":"bolt"}"#.utf8)
            )
        )

        let client = NetworkClient(
            configuration: makeConfiguration(retryPolicies: []),
            transport: transport
        )

        let model = try await client.request(endpoint)

        XCTAssertEqual(model, MockModel(id: 1, name: "bolt"))
    }

    func testDefaultConfigurationRequestDataReturnsRawTransportResponse() async throws {
        let endpoint = MockJSONEndpoint()
        let transport = StaticTransport(
            response: try makeTransportResponse(
                path: endpoint.path,
                statusCode: 200,
                data: Data(#"{"id":1,"name":"bolt"}"#.utf8),
                headers: ["X-Trace": "trace-1"]
            )
        )

        let client = NetworkClient(
            configuration: makeConfiguration(retryPolicies: []),
            transport: transport
        )

        let response = try await client.requestData(endpoint)

        XCTAssertEqual(response.response.statusCode, 200)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "X-Trace"), "trace-1")
        XCTAssertEqual(response.data, Data(#"{"id":1,"name":"bolt"}"#.utf8))
    }
}
