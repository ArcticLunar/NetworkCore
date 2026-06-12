// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义请求发出前的异步适配钩子。

import Foundation

/// 在请求交给 transport 前修改 URLRequest。
public protocol RequestInterceptor {
    /// 返回适配后的请求，可用于注入鉴权头、签名或追踪字段。
    func adapt(
        _ request: URLRequest,
        context: NetworkRequestContext
    ) async throws -> URLRequest
}
