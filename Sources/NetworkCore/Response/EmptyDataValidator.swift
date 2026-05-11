// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct EmptyDataValidator: ResponseValidator {
    public init() {}

    public func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        let allowsEmptyBody =
            context.expectsEmptyResponseBody
            || context.method == .head
            || [204, 205, 304].contains(response.response.statusCode)

        if response.data.isEmpty && allowsEmptyBody == false {
            throw NetworkError.emptyData
        }
    }
}
