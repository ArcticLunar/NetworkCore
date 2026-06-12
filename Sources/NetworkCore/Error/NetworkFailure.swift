// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 将错误分类和请求上下文组合成最终上抛的失败对象。

import Foundation

/// 带有 `NetworkErrorContext` 的网络失败。
public struct NetworkFailure: Error {
    /// 结构化错误分类。
    public let error: NetworkError
    /// 失败发生时的请求上下文。
    public let context: NetworkErrorContext

    public init(error: NetworkError, context: NetworkErrorContext) {
        self.error = error
        self.context = context
    }
}
