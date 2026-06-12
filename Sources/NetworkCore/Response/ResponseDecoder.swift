// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义响应 body 到业务模型的解码接口。

import Foundation

/// 将 `TransportResponse` 解码为端点声明的响应类型。
public protocol ResponseDecoder {
    /// 返回解码结果和安全解码警告数量。
    func decode<T: Decodable>(
        _ type: T.Type,
        from response: TransportResponse,
        decoder: JSONDecoder,
        context: NetworkRequestContext,
        policy: NetworkDecodingPolicy
    ) throws -> DecodedNetworkResponse<T>
}
