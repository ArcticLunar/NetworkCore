// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 持久化后台下载恢复所需的请求、目标路径和 resume data。

import Foundation

/// 可恢复后台下载的持久化记录。
public struct BackgroundDownloadRecord: Codable, Equatable, Sendable {
    /// URLRequest 的可编码快照。
    public struct RequestSnapshot: Codable, Equatable, Sendable {
        public let url: URL
        public let method: String
        public let headers: [String: String]
        public let timeoutInterval: TimeInterval?

        public init(
            url: URL,
            method: String,
            headers: [String: String] = [:],
            timeoutInterval: TimeInterval? = nil
        ) {
            self.url = url
            self.method = method
            self.headers = headers
            self.timeoutInterval = timeoutInterval
        }

        public init(request: URLRequest) throws {
            guard let url = request.url else {
                throw NetworkError.invalidRequest(
                    "Background download request is missing URL"
                )
            }

            self.init(
                url: url,
                method: request.httpMethod ?? HTTPMethod.get.rawValue,
                headers: request.allHTTPHeaderFields ?? [:],
                timeoutInterval: request.timeoutInterval > 0
                    ? request.timeoutInterval
                    : nil
            )
        }

        public func makeURLRequest() -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = timeoutInterval ?? 0

            headers.forEach {
                request.setValue($1, forHTTPHeaderField: $0)
            }

            return request
        }
    }

    /// 请求观测信息快照，供进程恢复后继续写日志和 metrics。
    public struct ObservabilitySnapshot: Codable, Equatable, Sendable {
        public let requestID: String
        public let environmentName: String
        public let path: String
        public let method: String

        public init(
            requestID: String,
            environmentName: String,
            path: String,
            method: String
        ) {
            self.requestID = requestID
            self.environmentName = environmentName
            self.path = path
            self.method = method
        }

        public init(context: NetworkRequestContext) {
            self.init(
                requestID: context.requestID,
                environmentName: context.environmentName,
                path: context.path,
                method: context.method.rawValue
            )
        }
    }

    public let identifier: String
    public let request: RequestSnapshot
    public let destinationURL: URL
    public let createdAt: Date
    public let observability: ObservabilitySnapshot?
    public var resumeData: Data?

    public init(
        identifier: String,
        request: RequestSnapshot,
        destinationURL: URL,
        createdAt: Date = Date(),
        observability: ObservabilitySnapshot? = nil,
        resumeData: Data? = nil
    ) {
        self.identifier = identifier
        self.request = request
        self.destinationURL = destinationURL
        self.createdAt = createdAt
        self.observability = observability
        self.resumeData = resumeData
    }

    public init(
        identifier: String,
        request: URLRequest,
        destinationURL: URL,
        createdAt: Date = Date(),
        observability: ObservabilitySnapshot? = nil,
        resumeData: Data? = nil
    ) throws {
        try self.init(
            identifier: identifier,
            request: RequestSnapshot(request: request),
            destinationURL: destinationURL,
            createdAt: createdAt,
            observability: observability,
            resumeData: resumeData
        )
    }
}

/// 后台下载恢复记录 store。
public protocol DownloadResumeStore: Sendable {
    func loadAllRecords() throws -> [BackgroundDownloadRecord]
    func loadRecord(
        for identifier: String
    ) throws -> BackgroundDownloadRecord?
    func save(_ record: BackgroundDownloadRecord) throws
    func removeRecord(for identifier: String) throws
}

/// 使用 JSON 文件保存后台下载恢复记录的默认 store。
public final class FileDownloadResumeStore: DownloadResumeStore, @unchecked Sendable {
    public let directoryURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        directoryURL: URL = FileDownloadResumeStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        // 使用 Date bitPattern 持久化，避免不同 locale 或格式化策略影响恢复记录。
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let bitPattern = try container.decode(UInt64.self)
            return Date(
                timeIntervalSinceReferenceDate: TimeInterval(bitPattern: bitPattern)
            )
        }
    }

    public func loadAllRecords() throws -> [BackgroundDownloadRecord] {
        try lock.withLock {
            try ensureDirectoryIfNeeded()

            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )

            return try urls
                .filter { $0.pathExtension == "json" }
                .map(loadRecord(from:))
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    public func loadRecord(
        for identifier: String
    ) throws -> BackgroundDownloadRecord? {
        try lock.withLock {
            try ensureDirectoryIfNeeded()

            let fileURL = recordURL(for: identifier)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }

            return try loadRecord(from: fileURL)
        }
    }

    public func save(_ record: BackgroundDownloadRecord) throws {
        try lock.withLock {
            try ensureDirectoryIfNeeded()

            let data = try encoder.encode(record)
            try data.write(to: recordURL(for: record.identifier), options: .atomic)
        }
    }

    public func removeRecord(for identifier: String) throws {
        try lock.withLock {
            let fileURL = recordURL(for: identifier)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                return
            }

            try fileManager.removeItem(at: fileURL)
        }
    }

    public static func defaultDirectoryURL() -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseDirectory
            .appendingPathComponent(
                "NetworkCoreBackgroundTransfer",
                isDirectory: true
            )
    }

    private func ensureDirectoryIfNeeded() throws {
        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
    }

    private func recordURL(for identifier: String) -> URL {
        directoryURL.appendingPathComponent("\(identifier).json")
    }

    private func loadRecord(from url: URL) throws -> BackgroundDownloadRecord {
        let data = try Data(contentsOf: url)
        return try decoder.decode(BackgroundDownloadRecord.self, from: data)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
