// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 从非 2xx 响应 body 中提取服务端错误信息。

import Foundation

/// 服务端错误 payload 解码器。
public struct ServerErrorDecoder {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONCoderFactory.defaultDecoder()) {
        self.decoder = decoder
    }

    public func decode(from data: Data) -> ServerErrorPayload? {
        guard data.isEmpty == false else { return nil }

        // 先尝试直接解析错误结构，再兼容通用 API envelope。
        if let payload = try? decoder.decode(ServerErrorPayload.self, from: data),
           payload.isMeaningful {
            return payload
        }

        if let envelope = try? decoder.decode(APIResponseEnvelope<AnyCodable>.self, from: data) {
            let payload = ServerErrorPayload(
                code: envelope.code,
                message: envelope.message,
                requestID: envelope.requestId,
                traceID: envelope.traceId
            )
            return payload.isMeaningful ? payload : nil
        }

        return nil
    }
}
