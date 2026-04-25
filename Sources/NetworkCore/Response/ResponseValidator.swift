public protocol ResponseValidator {
    func validate(
        _ response: TransportResponse,
        context: NetworkRequestContext
    ) throws
}
