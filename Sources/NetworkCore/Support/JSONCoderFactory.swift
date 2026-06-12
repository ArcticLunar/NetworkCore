// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供框架默认 JSONEncoder / JSONDecoder。

import Foundation

/// JSON 编解码器工厂。
public enum JSONCoderFactory {
    /// 默认响应解码器。
    public static func defaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }

    /// 默认请求编码器，日期按毫秒时间戳输出。
    public static func defaultEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}
