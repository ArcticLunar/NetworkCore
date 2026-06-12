// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 使用 JSONEncoder 实现请求 body 编码。

import Foundation

/// 默认 JSON 请求编码器。
public struct JSONRequestEncoder: RequestEncoder {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONCoderFactory.defaultEncoder()) {
        self.encoder = encoder
    }

    /// 使用配置好的 JSONEncoder 编码请求体。
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
