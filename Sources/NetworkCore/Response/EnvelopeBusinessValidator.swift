// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 使用业务 envelope 校验 code 和 unauthorized 状态。

import Foundation

/// 基于 `ResponseEnvelope` 的业务响应 validator。
public struct EnvelopeBusinessValidator<Envelope: ResponseEnvelope>: BusinessResponseValidator {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONCoderFactory.defaultDecoder()) {
        self.decoder = decoder
    }

    public func validate(
        data: Data,
        response: HTTPURLResponse,
        context: NetworkRequestContext
    ) throws {
        let envelope: Envelope

        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw NetworkError.decoding(underlying: error, data: data)
        }

        if Envelope.unauthorizedCodes.contains(envelope.safeCode) {
            throw NetworkError.unauthorized
        }

        // HTTP 成功不代表业务成功，业务失败需要带原始 data 上抛给调用方排障。
        guard envelope.isSuccess else {
            throw NetworkError.business(
                code: envelope.safeCode,
                message: envelope.safeMessage,
                data: data
            )
        }
    }
}
