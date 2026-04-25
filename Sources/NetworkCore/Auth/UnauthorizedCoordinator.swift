public actor UnauthorizedCoordinator {
    private let handler: any UnauthorizedHandler
    private var hasHandled = false

    public init(handler: any UnauthorizedHandler) {
        self.handler = handler
    }

    public func handleIfNeeded() async {
        guard hasHandled == false else { return }
        hasHandled = true
        await handler.handleUnauthorized()
    }

    public func reset() {
        hasHandled = false
    }
}
