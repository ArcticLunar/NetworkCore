// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 校验响应 body 是否允许为空。

import Foundation

/// 拦截意外空 body，避免后续解码错误掩盖真实响应契约问题。
public struct EmptyDataValidator: ResponseValidator {
    public init() {}

    public func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws {
        // HEAD、204、205、304 和显式 EmptyResponse 都允许没有 body。
        let allowsEmptyBody =
            context.expectsEmptyResponseBody
            || context.method == .head
            || [204, 205, 304].contains(response.response.statusCode)

        if response.data.isEmpty && allowsEmptyBody == false {
            throw NetworkError.emptyData
        }
    }
}
