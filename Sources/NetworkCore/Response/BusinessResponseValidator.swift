// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义 HTTP 成功后对业务 envelope 的校验接口。

import Foundation

/// 校验响应 body 中的业务 code、message 或登录态。
public protocol BusinessResponseValidator {
    /// 抛错会阻止响应继续解码为端点业务模型。
    func validate(
        data: Data,
        response: HTTPURLResponse,
        context: NetworkRequestContext
    ) throws
}
