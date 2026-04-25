public protocol UnauthorizedHandler {
    func handleUnauthorized() async
}

public struct NoopUnauthorizedHandler: UnauthorizedHandler {
    public init() {}

    public func handleUnauthorized() async {}
}
