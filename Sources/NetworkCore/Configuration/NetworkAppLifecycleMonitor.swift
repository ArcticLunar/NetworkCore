// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 抽象应用生命周期，让流式重连可以等待应用回到活跃状态。

import Foundation

/// 应用生命周期状态。
public enum NetworkAppLifecycleState: Equatable, Sendable {
    case active
    case inactive
}

/// 提供当前生命周期状态，并可等待应用恢复活跃。
public protocol NetworkAppLifecycleMonitor: Sendable {
    /// 返回当前应用状态。
    func currentState() async -> NetworkAppLifecycleState
    /// 挂起直到应用处于 active 状态。
    func waitUntilActive() async
}

/// 默认实现，适用于没有接入真实生命周期监控的场景。
public actor AlwaysActiveNetworkAppLifecycleMonitor: NetworkAppLifecycleMonitor {
    public init() {}

    public func currentState() -> NetworkAppLifecycleState {
        .active
    }

    public func waitUntilActive() async {}
}
