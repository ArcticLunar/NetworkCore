public enum UnauthorizedStrategy: Equatable, Sendable {
    case invalidateSessionOnce
    case refreshAndRetry(maxRetryCount: Int)
}
