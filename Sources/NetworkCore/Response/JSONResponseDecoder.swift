// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供严格 JSON 解码实现。

import Foundation

/// 严格 JSON 响应解码器，任何解码失败都会直接抛错。
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
