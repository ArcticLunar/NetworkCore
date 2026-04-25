import Foundation

public protocol ResponseDecoder {
    func decode<T: Decodable>(
        _ type: T.Type,
        from response: TransportResponse,
        decoder: JSONDecoder,
        context: NetworkRequestContext,
        policy: NetworkDecodingPolicy
    ) throws -> DecodedNetworkResponse<T>
}
