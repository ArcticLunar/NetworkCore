// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 定义网络路径状态、可达性要求和不可用原因。

import Foundation

/// 当前网络是否可用。
public enum NetworkPathAvailability: String, Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

/// 当前网络使用的接口类型。
public enum NetworkPathInterface: String, CaseIterable, Hashable, Sendable {
    case wifi
    case cellular
    case wiredEthernet
    case loopback
    case other
}

/// 当前网络路径快照。
public struct NetworkPathStatus: Equatable, Sendable {
    public let availability: NetworkPathAvailability
    public let interfaces: Set<NetworkPathInterface>
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(
        availability: NetworkPathAvailability,
        interfaces: Set<NetworkPathInterface> = [],
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.availability = availability
        self.interfaces = interfaces
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    public static var unsatisfied: Self {
        NetworkPathStatus(availability: .unsatisfied)
    }

    public static var requiresConnection: Self {
        NetworkPathStatus(availability: .requiresConnection)
    }

    public static func satisfied(
        interfaces: Set<NetworkPathInterface> = [],
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) -> Self {
        NetworkPathStatus(
            availability: .satisfied,
            interfaces: interfaces,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    public var isReachable: Bool {
        availability == .satisfied
    }
}

/// 单个请求对网络路径的约束。
public struct NetworkReachabilityRequirement: Equatable, Sendable {
    public let allowsCellular: Bool
    public let allowsExpensive: Bool
    public let allowsConstrained: Bool

    public init(
        allowsCellular: Bool = true,
        allowsExpensive: Bool = true,
        allowsConstrained: Bool = true
    ) {
        self.allowsCellular = allowsCellular
        self.allowsExpensive = allowsExpensive
        self.allowsConstrained = allowsConstrained
    }

    public static let any = NetworkReachabilityRequirement()
    public static let wifiOnly = NetworkReachabilityRequirement(
        allowsCellular: false
    )
    public static let unconstrained = NetworkReachabilityRequirement(
        allowsConstrained: false
    )

    public func isSatisfied(by status: NetworkPathStatus) -> Bool {
        // 先判断基础可达，再判断蜂窝、昂贵网络和低数据模式约束。
        guard status.isReachable else {
            return false
        }

        guard allowsCellular || status.interfaces.contains(.cellular) == false else {
            return false
        }

        guard allowsExpensive || status.isExpensive == false else {
            return false
        }

        guard allowsConstrained || status.isConstrained == false else {
            return false
        }

        return true
    }

    public func restrictionReason(
        for status: NetworkPathStatus
    ) -> NetworkAccessRestrictionReason {
        guard status.isReachable else {
            return .unavailable
        }

        if allowsCellular == false, status.interfaces.contains(.cellular) {
            return .requiresNonCellularConnection
        }

        if allowsExpensive == false, status.isExpensive {
            return .expensiveNetwork
        }

        if allowsConstrained == false, status.isConstrained {
            return .constrainedNetwork
        }

        return .unavailable
    }
}

/// 当前网络不满足要求时，客户端应该立即失败还是等待恢复。
public enum ReachabilityUnsatisfiedBehavior: Equatable, Sendable {
    case failFast
    case waitForConnectivity(timeout: TimeInterval?)

    var waitsForConnectivity: Bool {
        switch self {
        case .failFast:
            return false
        case .waitForConnectivity:
            return true
        }
    }
}

/// 请求被网络条件拦截时的原因。
public enum NetworkAccessRestrictionReason: Equatable, Sendable {
    case unavailable
    case requiresNonCellularConnection
    case constrainedNetwork
    case expensiveNetwork
    case expensiveUploadTooLarge(maxBytes: Int, actualBytes: Int)
    case constrainedUploadTooLarge(maxBytes: Int, actualBytes: Int)
}
