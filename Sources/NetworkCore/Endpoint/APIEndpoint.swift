import Foundation

public protocol APIEndpoint {
    associatedtype Response: Decodable

    var path: String { get }
    var method: HTTPMethod { get }
    var task: RequestTask { get }
    var headers: [String: String] { get }
    var authorization: AuthorizationRequirement { get }
    var options: RequestOptions { get }
    var acceptableContentTypes: [String] { get }
    var requestEncoder: (any RequestEncoder)? { get }
    var decoder: JSONDecoder { get }
    var decodingPolicy: NetworkDecodingPolicy? { get }
}

public extension APIEndpoint {
    var headers: [String: String] { [:] }
    var authorization: AuthorizationRequirement { .inheritGlobal }
    var options: RequestOptions {
        RequestOptions(
            isIdempotent: method.isIdempotentByDefault
        )
    }
    var acceptableContentTypes: [String] { ["application/json"] }
    var requestEncoder: (any RequestEncoder)? { nil }
    var decoder: JSONDecoder { JSONCoderFactory.defaultDecoder() }
    var decodingPolicy: NetworkDecodingPolicy? { nil }
}
