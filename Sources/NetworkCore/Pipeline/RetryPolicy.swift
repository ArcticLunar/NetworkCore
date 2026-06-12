// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义请求失败或可重试响应后的 retry 决策接口。

import Foundation

/// 根据请求、结果和上下文判断是否 retry。
public protocol RetryPolicy {
    /// 返回 retry 决策；`retryCount` 表示当前已经发生的 retry 次数。
    func evaluate(
        request: URLRequest,
        result: Result<TransportResponse, Error>,
        retryCount: Int,
        context: NetworkRequestContext
    ) async -> RetryDecision
}
