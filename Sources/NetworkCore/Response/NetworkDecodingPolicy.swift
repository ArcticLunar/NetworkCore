// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义响应解码的严格度和解码结果元信息。

import Foundation

/// JSON 解码策略。
public enum NetworkDecodingPolicy: Equatable, Sendable {
    /// 严格解码，字段类型不匹配会失败。
    case strict
    /// 容错解码，配合 safe decoding helper 记录 warning 并尽量产出结果。
    case safe
}

/// 解码后的值以及容错解码产生的 warning 数量。
public struct DecodedNetworkResponse<Value> {
    /// 解码后的业务值。
    public let value: Value
    /// 容错解码期间记录的 warning 数量。
    public let warningCount: Int

    public init(
        value: Value,
        warningCount: Int = 0
    ) {
        self.value = value
        self.warningCount = max(0, warningCount)
    }
}
