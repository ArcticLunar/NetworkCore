import Foundation

public protocol ResponseEnvelope: Decodable {
    associatedtype Payload: Decodable

    var code: Int? { get }
    var message: String? { get }
    var requestId: String? { get }
    var traceId: String? { get }
    var data: Payload? { get }

    static var successCodes: Set<Int> { get }
    static var unauthorizedCodes: Set<Int> { get }
}

public extension ResponseEnvelope {
    static var successCodes: Set<Int> { [0, 200] }
    static var unauthorizedCodes: Set<Int> { [401] }

    var safeCode: Int { code ?? -1 }
    var safeMessage: String { message ?? "" }
    var isSuccess: Bool { Self.successCodes.contains(safeCode) }
}
