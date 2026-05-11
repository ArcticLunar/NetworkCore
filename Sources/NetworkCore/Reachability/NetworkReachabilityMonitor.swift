// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation
#if canImport(Network)
import Network
#endif

public protocol NetworkReachabilityMonitor: Sendable {
    func currentPathStatus() async -> NetworkPathStatus
    func waitUntilSatisfied(
        _ requirement: NetworkReachabilityRequirement,
        timeout: TimeInterval?
    ) async -> NetworkPathStatus?
}

#if canImport(Network)
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
