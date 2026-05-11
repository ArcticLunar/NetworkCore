// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct NetworkFailure: Error {
    public let error: NetworkError
    public let context: NetworkErrorContext

    public init(error: NetworkError, context: NetworkErrorContext) {
        self.error = error
        self.context = context
    }
}
