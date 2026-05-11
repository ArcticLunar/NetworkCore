// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol ResponseValidator {
    func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws
}
