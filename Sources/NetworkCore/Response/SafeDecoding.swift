// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供容错解码 helper，用于兼容线上接口字段类型漂移或局部脏数据。

import Foundation

/// 为 `Defaulted` 提供字段缺失或类型不匹配时的默认值。
public protocol SafeDecodingDefaultValueProvider {
    associatedtype Value: Decodable
    static var defaultValue: Value { get }
}

/// 字段解码失败时回退到 Provider 默认值，并记录一次 warning。
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

/// 数组元素局部解码失败时丢弃坏元素，保留其它可用元素。
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

/// 字典 value 局部解码失败时丢弃坏 key，保留其它可用键值。
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

/// 兼容服务端把整数返回为字符串的字段。
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

/// 兼容服务端把布尔值返回为字符串或 0/1 的字段。
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
    // 使用 TaskLocal 收集当前解码任务中的容错 warning，避免污染并发请求。
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
            // safe 模式只在声明了容错 wrapper/helper 的字段上降级，普通字段仍按系统解码失败。
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
    /// 让缺失字段也可以通过 `@Defaulted` 回退默认值。
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
