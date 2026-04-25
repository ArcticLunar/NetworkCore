public enum AuthorizationRequirement: Equatable, Sendable {
    case none
    case bearerToken
    case custom(String)
    case inheritGlobal
}
