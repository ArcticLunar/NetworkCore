// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct SafeJSONResponseDecoder: ResponseDecoder {
    public init() {}

    public func decode<T: Decodable>(
        _ type: T.Type,
        from response: TransportResponse,
        decoder: JSONDecoder,
        context: NetworkRequestContext,
        policy: NetworkDecodingPolicy
    ) throws -> DecodedNetworkResponse<T> {
        do {
            return try NetworkDecodingSupport.decode(
                T.self,
                from: response.data,
                decoder: decoder,
                policy: policy
            )
        } catch {
            throw NetworkError.decoding(underlying: error, data: response.data)
        }
    }
}
