// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 提供类型擦除的 Codable / Encodable 包装，用于动态 JSON 字段和泛型请求体。

import Foundation

/// 可以承载基础 JSON 值、数组和字典的类型擦除 Codable。
public struct AnyCodable: Codable {
    public let value: Any?

    public init(_ value: Any?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = nil
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map(\.value)
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues(\.value)
        } else {
            value = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case nil:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value"
            )
            throw EncodingError.invalidValue(value as Any, context)
        }
    }
}

/// 将任意 Encodable 值包装成统一的 Encodable 类型。
public struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    public init<T: Encodable>(_ value: T) {
        encodeClosure = value.encode
    }

    public init(_ value: any Encodable) {
        encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
