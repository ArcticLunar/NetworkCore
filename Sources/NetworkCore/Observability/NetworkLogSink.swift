// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义结构化日志输出端口。

/// 接收已经脱敏并结构化的网络日志记录。
public protocol NetworkLogSink {
    /// 输出一条日志记录。
    func log(_ record: NetworkLogRecord)
}
