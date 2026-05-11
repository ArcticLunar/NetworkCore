// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public enum UnauthorizedStrategy: Equatable, Sendable {
    case invalidateSessionOnce
    case refreshAndRetry(maxRetryCount: Int)
}
