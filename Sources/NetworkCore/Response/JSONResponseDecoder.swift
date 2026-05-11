// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct JSONResponseDecoder: ResponseDecoder {
    public init() {}

    public func decode<T: Decodable>(
        _ type: T.Type,
        from response: TransportResponse,
        decoder: JSONDecoder,
        context: NetworkRequestContext,
        policy: NetworkDecodingPolicy
    ) throws -> DecodedNetworkResponse<T> {
        do {
            return DecodedNetworkResponse(
                value: try decoder.decode(T.self, from: response.data)
            )
        } catch {
            throw NetworkError.decoding(underlying: error, data: response.data)
        }
    }
}
