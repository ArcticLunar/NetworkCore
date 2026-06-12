// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义响应进入解码前的同步校验接口。

/// 校验 transport 响应是否满足协议层要求。
public protocol ResponseValidator {
    /// 抛错会中断后续 validator、业务校验和解码流程。
    func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws
}
