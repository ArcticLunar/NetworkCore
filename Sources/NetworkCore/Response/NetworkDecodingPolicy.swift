// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public enum NetworkDecodingPolicy: Equatable, Sendable {
    case strict
    case safe
}

public struct DecodedNetworkResponse<Value> {
    public let value: Value
    public let warningCount: Int

    public init(
        value: Value,
        warningCount: Int = 0
    ) {
        self.value = value
        self.warningCount = max(0, warningCount)
    }
}
