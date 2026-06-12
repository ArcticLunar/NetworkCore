// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供一套默认 API envelope 实现，适配常见 code/message/data 响应结构。

import Foundation

/// 默认业务响应外壳。
public struct APIResponseEnvelope<T: Decodable>: ResponseEnvelope {
    public let code: Int?
    public let message: String?
    public let requestId: String?
    public let traceId: String?
    public let data: T?

    public init(
        code: Int?,
        message: String?,
        requestId: String?,
        traceId: String?,
        data: T?
    ) {
        self.code = code
        self.message = message
        self.requestId = requestId
        self.traceId = traceId
        self.data = data
    }
}
