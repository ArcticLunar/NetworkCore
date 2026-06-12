// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 支持 strict / safe 两种策略的 JSON 响应解码器。

import Foundation

/// 默认响应解码器，safe 模式下会收集容错解码警告数量。
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
