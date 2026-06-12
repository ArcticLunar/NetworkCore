// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 抽象系统网络可达性监听，供请求前置 gating 和离线重试使用。

import Foundation
#if canImport(Network)
import Network
#endif

/// 提供当前网络路径状态，并支持等待满足指定网络要求。
public protocol NetworkReachabilityMonitor: Sendable {
    /// 返回当前网络路径快照。
    func currentPathStatus() async -> NetworkPathStatus
    /// 等待网络满足指定要求；超时或取消时返回 nil。
    func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus?
}

#if canImport(Network)
/// 基于 `NWPathMonitor` 的系统网络可达性实现。
public final actor SystemNetworkReachabilityMonitor: NetworkReachabilityMonitor {
    private struct Waiter {
        let requirement: NetworkReachabilityRequirement
        let continuation: CheckedContinuation<NetworkPathStatus?, Never>
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var currentStatus: NetworkPathStatus
    private var waiters: [UUID: Waiter] = [:]

    public init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "NetworkCore.NetworkReachabilityMonitor")
        currentStatus = NetworkPathStatus(path: monitor.currentPath)

        monitor.pathUpdateHandler = { [weak self] path in
            let status = NetworkPathStatus(path: path)
            Task {
                await self?.handle(pathStatus: status)
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public func currentPathStatus() -> NetworkPathStatus {
        currentStatus
    }

    public func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus? {
        if requirement.isSatisfied(by: currentStatus) {
            return currentStatus
        }

        let identifier = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    waiters[identifier] = Waiter(
                        requirement: requirement,
                        continuation: continuation
                    )

                    guard let timeout, timeout > 0 else {
                        return
                    }

                    // 每个 waiter 自己管理超时，避免一个全局 timer 影响其它等待者。
                    Task {
                        try? await Task.sleep(
                            nanoseconds: UInt64(timeout * 1_000_000_000)
                        )
                        resumeWaiterIfNeeded(
                            identifier,
                            returning: nil
                        )
                    }
                }
            },
            onCancel: {
                Task {
                    await self.resumeWaiterIfNeeded(
                        identifier,
                        returning: nil
                    )
                }
            }
        )
    }

    private func handle(pathStatus: NetworkPathStatus) {
        currentStatus = pathStatus

        let satisfiedIdentifiers = waiters.compactMap { identifier, waiter in
            waiter.requirement.isSatisfied(by: pathStatus) ? identifier : nil
        }

        for identifier in satisfiedIdentifiers {
            guard let waiter = waiters.removeValue(forKey: identifier) else {
                continue
            }

            waiter.continuation.resume(returning: pathStatus)
        }
    }

    private func resumeWaiterIfNeeded(
        _ identifier: UUID,
        returning status: NetworkPathStatus?
    ) {
        guard let waiter = waiters.removeValue(forKey: identifier) else {
            return
        }

        waiter.continuation.resume(returning: status)
    }
}

private extension NetworkPathStatus {
    init(path: NWPath) {
        self.init(
            availability: NetworkPathAvailability(path.status),
            interfaces: Set(NetworkPathInterface.allCases.filter { interface in
                path.usesInterfaceType(interface.nwInterfaceType)
            }),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}

private extension NetworkPathAvailability {
    init(_ status: NWPath.Status) {
        switch status {
        case .satisfied:
            self = .satisfied
        case .requiresConnection:
            self = .requiresConnection
        default:
            self = .unsatisfied
        }
    }
}

private extension NetworkPathInterface {
    var nwInterfaceType: NWInterface.InterfaceType {
        switch self {
        case .wifi:
            return .wifi
        case .cellular:
            return .cellular
        case .wiredEthernet:
            return .wiredEthernet
        case .loopback:
            return .loopback
        case .other:
            return .other
        }
    }
}
#endif
