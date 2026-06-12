// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 描述请求所属的后端环境。

import Foundation

/// 网络环境配置，通常对应 dev、staging、production 等后端入口。
public struct NetworkEnvironment: Equatable {
    /// 环境名，会进入错误上下文和观测事件。
    public let name: String
    /// 端点 path 会基于该 baseURL 拼接。
    public let baseURL: URL

    public init(name: String, baseURL: URL) {
        self.name = name
        self.baseURL = baseURL
    }
}
