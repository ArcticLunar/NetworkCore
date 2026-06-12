// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 将端点声明转换成 transport 可执行的 URLRequest 和任务类型。

import Foundation

/// 请求构建器，集中处理 URL、header、body、缓存策略和任务类型转换。
public enum RequestBuilder {
    /// 构建普通 HTTP 端点请求。
    public static func build<E: APIEndpoint>(
        endpoint: E,
        configuration: NetworkConfiguration
    ) throws -> TransportRequest {
        try build(
            path: endpoint.path,
            method: endpoint.method,
            task: endpoint.task,
            headers: endpoint.headers,
            options: endpoint.options,
            requestEncoder: endpoint.requestEncoder ?? configuration.requestEncoder,
            configuration: configuration
        )
    }

    /// 构建流式端点请求。
    public static func build<E: StreamingEndpoint>(
        endpoint: E,
        configuration: NetworkConfiguration
    ) throws -> TransportRequest {
        try build(
            path: endpoint.path,
            method: endpoint.method,
            task: endpoint.task,
            headers: endpoint.headers,
            options: endpoint.options,
            requestEncoder: endpoint.requestEncoder ?? configuration.requestEncoder,
            configuration: configuration
        )
    }

    private static func build(
        path: String,
        method: HTTPMethod,
        task: RequestTask,
        headers: [String: String],
        options: RequestOptions,
        requestEncoder: any RequestEncoder,
        configuration: NetworkConfiguration
    ) throws -> TransportRequest {
        let url = try buildURL(
            baseURL: configuration.environment.baseURL,
            path: path,
            task: task
        )

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = options.timeout ?? configuration.defaultTimeout
        request.cachePolicy = resolvedCachePolicy(
            options: options,
            configuration: configuration
        )

        // 先写全局 header，再写端点 header，让端点可以覆盖同名字段。
        configuration.defaultHeaders.forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }

        headers.forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }

        let task = try configure(
            task: task,
            request: &request,
            requestEncoder: requestEncoder
        )
        return TransportRequest(urlRequest: request, task: task)
    }

    private static func resolvedCachePolicy(
        options: RequestOptions,
        configuration: NetworkConfiguration
    ) -> URLRequest.CachePolicy {
        if let cachePolicy = options.cachePolicy {
            return cachePolicy
        }

        let networkCachePolicy = options.networkCachePolicy
            ?? configuration.defaultNetworkCachePolicy

        // 自定义缓存策略会映射回 URLRequest.CachePolicy，保证 transport 层仍使用系统语义。
        switch networkCachePolicy {
        case .useProtocolCachePolicy:
            return configuration.defaultCachePolicy
        case .reloadIgnoringCache,
             .returnCacheElseLoad,
             .staleWhileRevalidate,
             .memoryOnly,
             .disk,
             .noStore:
            return networkCachePolicy.urlRequestCachePolicy
        }
    }

    private static func buildURL(
        baseURL: URL,
        path: String,
        task: RequestTask
    ) throws -> URL {
        let fullURL = baseURL.appendingPathComponent(path)

        switch task {
        case .plain,
             .jsonBody,
             .formURLEncoded,
             .multipart,
             .upload,
             .download,
             .backgroundDownload:
            return fullURL

        case let .query(items):
            return try appendQueryItems(
                items,
                to: fullURL
            )

        case let .webSocket(queryItems, _):
            // WebSocket 端点复用 HTTP/HTTPS baseURL，但发起连接前必须转换成 ws/wss。
            let websocketURL = try websocketURL(from: fullURL)
            return try appendQueryItems(
                queryItems,
                to: websocketURL
            )
        }
    }

    private static func appendQueryItems(
        _ items: [URLQueryItem],
        to url: URL
    ) throws -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = items

        guard let resolvedURL = components?.url else {
            throw NetworkError.invalidRequest("Failed to build URL with query items")
        }

        return resolvedURL
    }

    private static func websocketURL(from url: URL) throws -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidRequest("Failed to build WebSocket URL")
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw NetworkError.invalidRequest("Unsupported WebSocket URL scheme")
        }

        guard let websocketURL = components.url else {
            throw NetworkError.invalidRequest("Failed to build WebSocket URL")
        }

        return websocketURL
    }

    private static func configure(
        task: RequestTask,
        request: inout URLRequest,
        requestEncoder: any RequestEncoder
    ) throws -> TransportTask {
        switch task {
        case .plain, .query:
            return .request

        case let .jsonBody(body):
            request.httpBody = try requestEncoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return .request

        case let .formURLEncoded(params):
            let value = try formURLEncodedString(params)
            request.httpBody = value.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            return .request

        case let .multipart(parts):
            let body = try MultipartFormEncoder.encode(parts: parts)
            request.setValue(
                "multipart/form-data; boundary=\(MultipartFormEncoder.boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            return .upload(data: body)

        case let .upload(data, contentType):
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            return .upload(data: data)

        case let .download(destination):
            return .download(destination: destination)

        case let .backgroundDownload(destination, transferIdentifier):
            return .backgroundDownload(
                destination: destination,
                transferIdentifier: transferIdentifier
            )

        case let .webSocket(_, subprotocols):
            if subprotocols.isEmpty == false {
                request.setValue(
                    subprotocols.joined(separator: ", "),
                    forHTTPHeaderField: "Sec-WebSocket-Protocol"
                )
            }

            return .request
        }
    }

    private static func formURLEncodedString(
        _ params: [String: String]
    ) throws -> String {
        guard params.isEmpty == false else {
            return ""
        }

        return try params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = try formURLEncodedComponent(key)
                let encodedValue = try formURLEncodedComponent(value)
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private static func formURLEncodedComponent(
        _ value: String
    ) throws -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._* ")

        guard let percentEncodedValue = value.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ) else {
            throw NetworkError.invalidRequest("Failed to encode form URL component")
        }

        return percentEncodedValue.replacingOccurrences(of: " ", with: "+")
    }
}
