// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public protocol UnauthorizedHandler {
    func handleUnauthorized() async
}

public struct NoopUnauthorizedHandler: UnauthorizedHandler {
    public init() {}

    public func handleUnauthorized() async {}
}
