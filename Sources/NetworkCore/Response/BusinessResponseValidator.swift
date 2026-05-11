// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol BusinessResponseValidator {
    func validate(
        data: Data,
        response: HTTPURLResponse,
        context: NetworkRequestContext
    ) throws
}
