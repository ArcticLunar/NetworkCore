// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

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
