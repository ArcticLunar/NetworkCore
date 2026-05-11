// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public protocol SafeDecodingDefaultValueProvider {
    associatedtype Value: Decodable
    static var defaultValue: Value { get }
}

@propertyWrapper
public struct Defaulted<Provider: SafeDecodingDefaultValueProvider>: Decodable {
    public var wrappedValue: Provider.Value

    public init() {
        self.wrappedValue = Provider.defaultValue
    }

    public init(wrappedValue: Provider.Value) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        do {
            wrappedValue = try container.decode(Provider.Value.self)
        } catch {
            SafeDecodingContext.collector?.recordWarning()
            wrappedValue = Provider.defaultValue
        }
    }
}

extension Defaulted: Equatable where Provider.Value: Equatable {}

public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(_ elements: [Element] = []) {
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []

        while container.isAtEnd == false {
            do {
                values.append(
                    try container.decode(Element.self)
                )
            } catch {
                SafeDecodingContext.collector?.recordWarning()
                _ = try? container.decode(DiscardedDecodableValue.self)
            }
        }

        elements = values
    }
}

public struct LossyDictionary<Value: Decodable>: Decodable {
    public let values: [String: Value]

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: DynamicCodingKey.self
        )
        var resolvedValues: [String: Value] = [:]

        for key in container.allKeys {
            do {
                resolvedValues[key.stringValue] = try container.decode(
                    Value.self,
                    forKey: key
                )
            } catch {
                SafeDecodingContext.collector?.recordWarning()
            }
        }

        values = resolvedValues
    }
}

extension LossyArray: Equatable where Element: Equatable {}
extension LossyDictionary: Equatable where Value: Equatable {}

public struct StringBackedInt: Decodable, Equatable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
            return
        }

        if let stringValue = try? container.decode(String.self),
           let intValue = Int(stringValue) {
            SafeDecodingContext.collector?.recordWarning()
            value = intValue
            return
        }

        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Int or String-backed Int"
            )
        )
    }
}

public struct StringBackedBool: Decodable, Equatable {
    public let value: Bool

    public init(_ value: Bool) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
            return
        }

        if let stringValue = try? container.decode(String.self) {
            let normalized = stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch normalized {
            case "true", "1", "yes", "y":
                SafeDecodingContext.collector?.recordWarning()
                value = true
                return
            case "false", "0", "no", "n":
                SafeDecodingContext.collector?.recordWarning()
                value = false
                return
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Bool or String-backed Bool"
            )
        )
    }
}

enum SafeDecodingContext {
    @TaskLocal static var collector: SafeDecodingCollector?
}

final class SafeDecodingCollector {
    private let lock = NSLock()
    private var warnings = 0

    func recordWarning() {
        lock.withLock {
            warnings += 1
        }
    }

    var warningCount: Int {
        lock.withLock { warnings }
    }
}

struct NetworkDecodingSupport {
    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder,
        policy: NetworkDecodingPolicy
    ) throws -> DecodedNetworkResponse<T> {
        switch policy {
        case .strict:
            return DecodedNetworkResponse(
                value: try decoder.decode(T.self, from: data)
            )

        case .safe:
            let collector = SafeDecodingCollector()
            let value = try SafeDecodingContext.$collector.withValue(collector) {
                try decoder.decode(T.self, from: data)
            }

            return DecodedNetworkResponse(
                value: value,
                warningCount: collector.warningCount
            )
        }
    }
}

public extension KeyedDecodingContainer {
    func decode<Provider>(
        _ type: Defaulted<Provider>.Type,
        forKey key: Key
    ) throws -> Defaulted<Provider> {
        if let value = try decodeIfPresent(type, forKey: key) {
            return value
        }

        SafeDecodingContext.collector?.recordWarning()
        return Defaulted()
    }
}

private struct DiscardedDecodableValue: Decodable {}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
