import Foundation

public struct EnvelopeBusinessValidator<Envelope: ResponseEnvelope>: BusinessResponseValidator {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONCoderFactory.defaultDecoder()) {
        self.decoder = decoder
    }

    public func validate(
        data: Data,
        response: HTTPURLResponse,
        context: NetworkRequestContext
    ) throws {
        let envelope: Envelope

        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw NetworkError.decoding(underlying: error, data: data)
        }

        if Envelope.unauthorizedCodes.contains(envelope.safeCode) {
            throw NetworkError.unauthorized
        }

        guard envelope.isSuccess else {
            throw NetworkError.business(
                code: envelope.safeCode,
                message: envelope.safeMessage,
                data: data
            )
        }
    }
}
