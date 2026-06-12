// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 抽象常见 API envelope，用于业务 code 校验和服务端错误解析。

import Foundation

/// 描述带 code、message、trace id 和 data 的响应外壳。
public protocol ResponseEnvelope: Decodable {
    associatedtype Payload: Decodable

    var code: Int? { get }
    var message: String? { get }
    var requestId: String? { get }
    var traceId: String? { get }
    var data: Payload? { get }

    static var successCodes: Set<Int> { get }
    static var unauthorizedCodes: Set<Int> { get }
}

public extension ResponseEnvelope {
    /// 默认成功 code，兼容业务 code 0 和 HTTP 风格 code 200。
    static var successCodes: Set<Int> { [0, 200] }
    /// 默认 unauthorized 业务 code。
    static var unauthorizedCodes: Set<Int> { [401] }

    var safeCode: Int { code ?? -1 }
    var safeMessage: String { message ?? "" }
    var isSuccess: Bool { Self.successCodes.contains(safeCode) }
}
