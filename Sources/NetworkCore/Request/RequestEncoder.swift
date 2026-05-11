// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol RequestEncoder {
    func encode<T: Encodable>(_ value: T) throws -> Data
}
