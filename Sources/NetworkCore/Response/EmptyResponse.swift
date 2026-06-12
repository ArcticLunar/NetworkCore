// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 表示端点预期没有响应 body。

/// 空响应占位模型，适用于 204 或只关心状态码的端点。
public struct EmptyResponse: Codable {
    public init() {}
}
