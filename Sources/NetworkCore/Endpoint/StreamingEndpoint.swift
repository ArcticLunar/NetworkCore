import Foundation

public protocol StreamingEndpoint {
    associatedtype Event: Sendable

    var path: String { get }
    var method: HTTPMethod { get }
    var task: RequestTask { get }
    var headers: [String: String] { get }
    var authorization: AuthorizationRequirement { get }
    var options: RequestOptions { get }
    var requestEncoder: (any RequestEncoder)? { get }
    var decoder: JSONDecoder { get }
    var decodingPolicy: NetworkDecodingPolicy? { get }
    var streamKind: NetworkStreamKind { get }

    func mapStreamEvent(_ event: NetworkStreamEvent) throws -> Event?
}

public extension StreamingEndpoint {
    var method: HTTPMethod { .get }
    var task: RequestTask { .plain }
    var headers: [String: String] { [:] }
    var authorization: AuthorizationRequirement { .inheritGlobal }
    var options: RequestOptions {
        RequestOptions(
            isIdempotent: method.isIdempotentByDefault
        )
    }
    var requestEncoder: (any RequestEncoder)? { nil }
    var decoder: JSONDecoder { JSONCoderFactory.defaultDecoder() }
    var decodingPolicy: NetworkDecodingPolicy? { nil }
}

public extension StreamingEndpoint where Event: Decodable {
    func mapStreamEvent(_ event: NetworkStreamEvent) throws -> Event? {
        switch event {
        case let .message(data):
            return try NetworkDecodingSupport.decode(
                Event.self,
                from: data,
                decoder: decoder,
                policy: decodingPolicy ?? .strict
            ).value

        case let .serverSentEvent(sseEvent):
            return try NetworkDecodingSupport.decode(
                Event.self,
                from: Data(sseEvent.data.utf8),
                decoder: decoder,
                policy: decodingPolicy ?? .strict
            ).value

        case .open, .closed:
            return nil
        }
    }
}
