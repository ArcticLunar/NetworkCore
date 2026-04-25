import Foundation

public protocol BusinessResponseValidator {
    func validate(
        data: Data,
        response: HTTPURLResponse,
        context: NetworkRequestContext
    ) throws
}
