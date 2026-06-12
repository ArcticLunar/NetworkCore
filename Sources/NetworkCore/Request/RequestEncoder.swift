// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义请求 body 编码抽象，支持全局和端点级覆盖。

import Foundation

/// 将 Encodable 值编码为请求 body 数据。
public protocol RequestEncoder {
    /// 返回可写入 `URLRequest.httpBody` 的二进制数据。
    func encode<T: Encodable>(_ value: T) throws -> Data
}
