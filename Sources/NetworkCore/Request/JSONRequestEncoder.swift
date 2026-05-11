// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct JSONRequestEncoder: RequestEncoder {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONCoderFactory.defaultEncoder()) {
        self.encoder = encoder
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}
