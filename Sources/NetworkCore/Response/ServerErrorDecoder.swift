// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct ServerErrorDecoder {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONCoderFactory.defaultDecoder()) {
        self.decoder = decoder
    }

    public func decode(from data: Data) -> ServerErrorPayload? {
        guard data.isEmpty == false else { return nil }

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
