// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 校验 HTTP 状态码，并尽量保留服务端错误 payload。

import Foundation

/// HTTP 状态码 validator。
public struct HTTPStatusCodeValidator: ResponseValidator {
    private let successCodes: ClosedRange<Int>
    private let serverErrorDecoder: ServerErrorDecoder

    public init(
        successCodes: ClosedRange<Int> = 200...299,
        serverErrorDecoder: ServerErrorDecoder = ServerErrorDecoder()
    ) {
        self.successCodes = successCodes
        self.serverErrorDecoder = serverErrorDecoder
    }

    public func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        let statusCode = response.response.statusCode

        if statusCode == 401 {
            throw NetworkError.unauthorized
        }

        guard successCodes.contains(statusCode) else {
            // 非 2xx 响应先尝试解析服务端错误包体，失败后再回退到纯状态码错误。
            if let payload = serverErrorDecoder.decode(from: response.data) {
                throw NetworkError.serverError(
                    statusCode: statusCode,
                    payload: payload,
                    data: response.data
                )
            }
            throw NetworkError.httpStatus(code: statusCode, data: response.data)
        }
    }
}
