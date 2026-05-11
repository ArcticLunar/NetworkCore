// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum NetworkAppLifecycleState: Equatable, Sendable {
    case active
    case inactive
}

public protocol NetworkAppLifecycleMonitor: Sendable {
    func currentState() async -> NetworkAppLifecycleState
    func waitUntilActive() async
}

public actor AlwaysActiveNetworkAppLifecycleMonitor: NetworkAppLifecycleMonitor {
    public init() {}

    public func currentState() -> NetworkAppLifecycleState {
        .active
    }

    public func waitUntilActive() async {}
}
