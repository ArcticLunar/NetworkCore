// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 管理后台下载的排队、暂停、恢复、进度广播和持久化恢复。

import Foundation

/// 后台下载管理器。
public final class BackgroundDownloadManager: @unchecked Sendable {
    public static let defaultSessionIdentifier =
        NetworkDefaults.defaultBackgroundDownloadSessionIdentifier()
    private static let successStatusCodeRange = 200..<300

    public let sessionIdentifier: String

    private let resumeStore: any DownloadResumeStore
    private let driver: any BackgroundDownloadDriving
    private let observers: [any BackgroundTransferObserver]
    private let fileManager: FileManager
    private let lock = NSLock()

    private var eventContinuations: [UUID: AsyncStream<BackgroundTransferEvent>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<BackgroundTransferStatus>.Continuation] = [:]
    private var pauseRequests: Set<String> = []
    private var cachedRecords: [String: BackgroundDownloadRecord] = [:]
    private var currentStatusesByIdentifier: [String: BackgroundTransferStatus] = [:]

    public convenience init(
        resumeStore: any DownloadResumeStore = FileDownloadResumeStore(),
        sessionIdentifier: String = defaultSessionIdentifier,
        observers: [any BackgroundTransferObserver] = [],
        fileManager: FileManager = .default
    ) {
        self.init(
            resumeStore: resumeStore,
            driver: URLSessionBackgroundDownloadDriver(
                sessionIdentifier: sessionIdentifier
            ),
            observers: observers,
            fileManager: fileManager
        )
    }

    init(
        resumeStore: any DownloadResumeStore,
        driver: any BackgroundDownloadDriving,
        observers: [any BackgroundTransferObserver] = [],
        fileManager: FileManager = .default
    ) {
        self.sessionIdentifier = driver.sessionIdentifier
        self.resumeStore = resumeStore
        self.driver = driver
        self.observers = observers
        self.fileManager = fileManager

        driver.setEventHandler { [weak self] event in
            self?.handleDriverEvent(event)
        }

        BackgroundTransferSystemCoordinator.shared.register(
            sessionIdentifier: driver.sessionIdentifier
        ) { [weak self] completionHandler in
            self?.handleEventsForBackgroundURLSession(
                completionHandler: completionHandler
            )
        }
    }

    deinit {
        BackgroundTransferSystemCoordinator.shared.unregister(
            sessionIdentifier: sessionIdentifier
        )
    }

    /// 订阅后台下载生命周期事件。
    public func events() -> AsyncStream<BackgroundTransferEvent> {
        let token = UUID()

        return AsyncStream { continuation in
            lock.withLock {
                eventContinuations[token] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                if let self {
                    self.lock.withLock {
                        _ = self.eventContinuations.removeValue(forKey: token)
                    }
                }
            }
        }
    }

    /// 订阅适合 UI 展示的后台下载状态快照。
    public func statusUpdates() -> AsyncStream<BackgroundTransferStatus> {
        let token = UUID()

        return AsyncStream { continuation in
            lock.withLock {
                statusContinuations[token] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                if let self {
                    self.lock.withLock {
                        _ = self.statusContinuations.removeValue(forKey: token)
                    }
                }
            }
        }
    }

    /// 创建后台下载任务并保存恢复记录。
    public func enqueueDownload(
        request: URLRequest,
        destination: URL,
        identifier: String? = nil,
        observability: BackgroundDownloadRecord.ObservabilitySnapshot? = nil
    ) async throws -> BackgroundTransferReceipt {
        let resolvedIdentifier = identifier ?? UUID().uuidString
        let record = try BackgroundDownloadRecord(
            identifier: resolvedIdentifier,
            request: request,
            destinationURL: destination,
            observability: observability
        )

        try resumeStore.save(record)
        cache(record)
        try await driver.startDownload(
            identifier: resolvedIdentifier,
            request: record.request.makeURLRequest(),
            destination: destination
        )

        let receipt = BackgroundTransferReceipt(
            identifier: resolvedIdentifier,
            destinationURL: destination
        )
        emit(
            .scheduled(receipt),
            record: record
        )
        return receipt
    }

    /// 暂停下载并保存 resume data。
    public func pauseDownload(
        identifier: String
    ) async throws -> BackgroundDownloadRecord {
        guard var record = try record(for: identifier) else {
            throw NetworkError.invalidRequest(
                "Missing background download record: \(identifier)"
            )
        }

        lock.withLock {
            _ = pauseRequests.insert(identifier)
        }

        let resumeData = try await driver.cancelDownload(identifier: identifier)
        record.resumeData = resumeData
        try resumeStore.save(record)
        cache(record)
        emit(
            .paused(record),
            record: record
        )
        return record
    }

    /// 使用 resume data 或原始请求恢复下载。
    public func resumeDownload(
        identifier: String
    ) async throws -> BackgroundTransferReceipt {
        guard var record = try record(for: identifier) else {
            throw NetworkError.invalidRequest(
                "Missing background download record: \(identifier)"
            )
        }

        let request = record.request.makeURLRequest()

        if let resumeData = record.resumeData {
            try await driver.resumeDownload(
                identifier: identifier,
                request: request,
                destination: record.destinationURL,
                resumeData: resumeData
            )
        } else {
            try await driver.startDownload(
                identifier: identifier,
                request: request,
                destination: record.destinationURL
            )
        }

        record.resumeData = nil
        try resumeStore.save(record)
        cache(record)

        let receipt = BackgroundTransferReceipt(
            identifier: identifier,
            destinationURL: record.destinationURL
        )
        emit(
            .resumed(receipt),
            record: record
        )
        return receipt
    }

    /// 恢复本地持久化的下载记录，并重新同步系统活跃任务。
    public func restorePersistedDownloads() async throws -> [BackgroundDownloadRecord] {
        try await driver.restoreActiveDownloads()
        let records = try resumeStore.loadAllRecords()
        cache(records)
        records.forEach {
            emit(
                .restored($0),
                record: $0
            )
        }
        return records
    }

    public func handleEventsForBackgroundURLSession(
        completionHandler: @escaping () -> Void
    ) {
        driver.attachBackgroundEventsCompletionHandler(completionHandler)

        // 系统唤醒后台 session 后，先恢复记录，确保后续事件能带上原请求上下文。
        Task { [weak self] in
            try? await self?.restorePersistedDownloads()
        }
    }

    public func record(
        for identifier: String
    ) throws -> BackgroundDownloadRecord? {
        if let cachedRecord = cachedRecord(for: identifier) {
            return cachedRecord
        }

        let loadedRecord = try resumeStore.loadRecord(for: identifier)

        if let loadedRecord {
            cache(loadedRecord)
        }

        return loadedRecord
    }

    public func status(
        for identifier: String
    ) -> BackgroundTransferStatus? {
        lock.withLock {
            currentStatusesByIdentifier[identifier]
        }
    }

    public func currentStatuses() -> [BackgroundTransferStatus] {
        lock.withLock {
            currentStatusesByIdentifier.values.sorted {
                let lhsDate = $0.createdAt ?? $0.updatedAt
                let rhsDate = $1.createdAt ?? $1.updatedAt

                if lhsDate == rhsDate {
                    return $0.identifier < $1.identifier
                }

                return lhsDate < rhsDate
            }
        }
    }

    private func emit(
        _ event: BackgroundTransferEvent,
        record: BackgroundDownloadRecord? = nil,
        duration: TimeInterval? = nil
    ) {
        let continuations = lock.withLock {
            Array(eventContinuations.values)
        }

        continuations.forEach {
            $0.yield(event)
        }

        let observation = BackgroundTransferObservation(
            event: event,
            record: record,
            duration: duration
        )

        observers.forEach {
            $0.backgroundTransferDidEmit(observation)
        }

        publishStatusIfNeeded(
            from: observation
        )
    }

    private func handleDriverEvent(_ event: BackgroundDownloadDriverEvent) {
        switch event {
        case let .progress(
            identifier,
            bytesWritten,
            totalBytesWritten,
            totalBytesExpected
        ):
            let record = observedRecord(for: identifier)

            emit(
                .progress(
                    identifier: identifier,
                    bytesWritten: bytesWritten,
                    totalBytesWritten: totalBytesWritten,
                    totalBytesExpected: totalBytesExpected
                ),
                record: record
            )

        case let .completed(identifier, temporaryFileURL, response):
            do {
                guard let record = try record(for: identifier) else {
                    return
                }

                if let statusCode = response?.statusCode,
                   Self.successStatusCodeRange.contains(statusCode) == false {
                    discardTemporaryFileIfPresent(at: temporaryFileURL)
                    emitFailure(
                        identifier: identifier,
                        record: record,
                        reason: .resolve(statusCode: statusCode),
                        description: "HTTP \(statusCode)",
                        resumeDataAvailable: false
                    )
                    return
                }

                try moveDownloadedFile(
                    from: temporaryFileURL,
                    to: record.destinationURL
                )
                try resumeStore.removeRecord(for: identifier)
                removeCachedRecord(for: identifier)

                let receipt = BackgroundTransferReceipt(
                    identifier: identifier,
                    destinationURL: record.destinationURL
                )
                emit(
                    .completed(
                        receipt: receipt,
                        response: response
                    ),
                    record: record,
                    duration: Date().timeIntervalSince(record.createdAt)
                )
            } catch {
                discardTemporaryFileIfPresent(at: temporaryFileURL)
                emitFailure(
                    identifier: identifier,
                    record: try? record(for: identifier),
                    reason: .resolve(error: error),
                    description: NetworkObservabilitySupport
                        .safeBackgroundFailureDescription(
                            reason: .resolve(error: error),
                            error: error
                        ),
                    resumeDataAvailable: false
                )
            }

        case let .failed(identifier, reason, description, resumeData):
            do {
                let wasPauseRequest = lock.withLock {
                    pauseRequests.remove(identifier) != nil
                }

                if wasPauseRequest,
                   var record = try record(for: identifier) {
                    if let resumeData {
                        record.resumeData = resumeData
                        try resumeStore.save(record)
                        cache(record)
                    }
                    return
                }

                var record = try record(for: identifier)

                if var unwrappedRecord = record,
                   let resumeData {
                    unwrappedRecord.resumeData = resumeData
                    try resumeStore.save(unwrappedRecord)
                    cache(unwrappedRecord)
                    record = unwrappedRecord
                }

                emit(
                    .failed(
                        identifier: identifier,
                        reason: reason,
                        description: safeFailureDescription(
                            reason: reason,
                            description: description
                        ),
                        resumeDataAvailable: resumeData != nil
                    ),
                    record: record,
                    duration: record.map {
                        Date().timeIntervalSince($0.createdAt)
                    }
                )
            } catch {
                emitFailure(
                    identifier: identifier,
                    record: try? record(for: identifier),
                    reason: .resolve(error: error),
                    description: NetworkObservabilitySupport
                        .safeBackgroundFailureDescription(
                            reason: .resolve(error: error),
                            error: error
                        ),
                    resumeDataAvailable: resumeData != nil
                )
            }
        }
    }

    private func moveDownloadedFile(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        let directoryURL = destinationURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func discardTemporaryFileIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    private func cache(_ record: BackgroundDownloadRecord) {
        lock.withLock {
            cachedRecords[record.identifier] = record
        }
    }

    private func cache(_ records: [BackgroundDownloadRecord]) {
        lock.withLock {
            records.forEach {
                cachedRecords[$0.identifier] = $0
            }
        }
    }

    private func cachedRecord(
        for identifier: String
    ) -> BackgroundDownloadRecord? {
        lock.withLock {
            cachedRecords[identifier]
        }
    }

    private func removeCachedRecord(for identifier: String) {
        lock.withLock {
            _ = cachedRecords.removeValue(forKey: identifier)
        }
    }

    private func observedRecord(
        for identifier: String
    ) -> BackgroundDownloadRecord? {
        if let record = cachedRecord(for: identifier) {
            return record
        }

        guard let record = try? resumeStore.loadRecord(for: identifier) else {
            return nil
        }

        cache(record)
        return record
    }

    private func emitFailure(
        identifier: String,
        record: BackgroundDownloadRecord?,
        reason: BackgroundTransferFailureReason,
        description: String,
        resumeDataAvailable: Bool
    ) {
        emit(
            .failed(
                identifier: identifier,
                reason: reason,
                description: description,
                resumeDataAvailable: resumeDataAvailable
            ),
            record: record,
            duration: record.map {
                Date().timeIntervalSince($0.createdAt)
            }
        )
    }

    private func safeFailureDescription(
        reason: BackgroundTransferFailureReason,
        description: String
    ) -> String {
        if description.hasPrefix("reason=") || description.hasPrefix("category=") {
            return description
        }

        return NetworkObservabilitySupport.safeBackgroundFailureDescription(
            reason: reason
        )
    }

    private func publishStatusIfNeeded(
        from observation: BackgroundTransferObservation
    ) {
        guard let status = makeStatus(from: observation) else {
            return
        }

        let continuations = lock.withLock {
            if case .completed = status.state {
                _ = currentStatusesByIdentifier.removeValue(forKey: status.identifier)
            } else {
                currentStatusesByIdentifier[status.identifier] = status
            }

            return Array(statusContinuations.values)
        }

        continuations.forEach {
            $0.yield(status)
        }
    }

    private func makeStatus(
        from observation: BackgroundTransferObservation
    ) -> BackgroundTransferStatus? {
        let identifier = statusIdentifier(from: observation.event)

        guard let identifier else {
            return nil
        }

        let previousStatus = lock.withLock {
            currentStatusesByIdentifier[identifier]
        }
        let record = observation.record
        let requestID = record?.observability?.requestID
            ?? previousStatus?.requestID
        let environmentName = record?.observability?.environmentName
            ?? previousStatus?.environmentName
        let method = resolvedMethod(
            record: record,
            previousStatus: previousStatus
        )
        let path = record?.observability?.path
            ?? previousStatus?.path
            ?? record?.request.url.path
        let destinationURL = record?.destinationURL
            ?? previousStatus?.destinationURL
        let createdAt = record?.createdAt
            ?? previousStatus?.createdAt
        let updatedAt = Date()
        let state: BackgroundTransferState

        switch observation.event {
        case .scheduled, .resumed:
            state = .pending

        case let .restored(record):
            if record.resumeData != nil {
                state = .paused(resumeDataAvailable: true)
            } else {
                state = .running(nil)
            }

        case let .paused(record):
            state = .paused(resumeDataAvailable: record.resumeData != nil)

        case let .progress(_, bytesWritten, totalBytesWritten, totalBytesExpected):
            state = .running(
                BackgroundTransferProgress(
                    bytesWritten: bytesWritten,
                    totalBytesWritten: totalBytesWritten,
                    totalBytesExpected: totalBytesExpected > 0
                        ? totalBytesExpected
                        : nil
                )
            )

        case let .completed(_, response):
            state = .completed(response: response)

        case let .failed(_, reason, description, resumeDataAvailable):
            state = .failed(
                reason: reason,
                description: description,
                resumeDataAvailable: resumeDataAvailable
            )
        }

        return BackgroundTransferStatus(
            identifier: identifier,
            requestID: requestID,
            environmentName: environmentName,
            method: method,
            path: path,
            destinationURL: destinationURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            state: state
        )
    }

    private func statusIdentifier(
        from event: BackgroundTransferEvent
    ) -> String? {
        switch event {
        case let .scheduled(receipt),
             let .resumed(receipt),
             let .completed(receipt, _):
            return receipt.identifier

        case let .restored(record),
             let .paused(record):
            return record.identifier

        case let .progress(identifier, _, _, _),
             let .failed(identifier, _, _, _):
            return identifier
        }
    }

    private func resolvedMethod(
        record: BackgroundDownloadRecord?,
        previousStatus: BackgroundTransferStatus?
    ) -> HTTPMethod? {
        if let rawValue = record?.observability?.method
            ?? record?.request.method {
            return HTTPMethod(rawValue: rawValue)
        }

        return previousStatus?.method
    }

}

// 隔离 URLSession 后台下载细节，便于测试替换 driver。
protocol BackgroundDownloadDriving: Sendable {
    var sessionIdentifier: String { get }

    func setEventHandler(
        _ handler: (@Sendable (BackgroundDownloadDriverEvent) -> Void)?
    )
    func attachBackgroundEventsCompletionHandler(
        _ handler: @escaping () -> Void
    )
    func startDownload(
        identifier: String,
        request: URLRequest,
        destination: URL
    ) async throws
    func resumeDownload(
        identifier: String,
        request: URLRequest,
        destination: URL,
        resumeData: Data
    ) async throws
    func cancelDownload(
        identifier: String
    ) async throws -> Data?
    func restoreActiveDownloads() async throws
}

// driver 回传给 manager 的底层下载事件。
enum BackgroundDownloadDriverEvent: Sendable {
    case progress(
        identifier: String,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    )
    case completed(
        identifier: String,
        temporaryFileURL: URL,
        response: BackgroundTransferResponse?
    )
    case failed(
        identifier: String,
        reason: BackgroundTransferFailureReason,
        description: String,
        resumeData: Data?
    )
}

private final class URLSessionBackgroundDownloadDriver:
    NSObject,
    URLSessionDownloadDelegate,
    URLSessionTaskDelegate,
    BackgroundDownloadDriving,
    @unchecked Sendable {

    private let lock = NSLock()
    private let configuredSessionIdentifier: String
    private let sessionDelegateQueue: OperationQueue
    private var eventHandler: (@Sendable (BackgroundDownloadDriverEvent) -> Void)?
    private var backgroundEventsCompletionHandler: (() -> Void)?
    private var tasksByIdentifier: [String: URLSessionDownloadTask] = [:]

    // URLSession 必须懒加载，确保 delegate 和 completion handler 注册顺序可控。
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: configuredSessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: sessionDelegateQueue
        )
    }()

    init(sessionIdentifier: String) {
        self.configuredSessionIdentifier = sessionIdentifier
        self.sessionDelegateQueue = OperationQueue()
        self.sessionDelegateQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    var sessionIdentifier: String {
        configuredSessionIdentifier
    }

    func setEventHandler(
        _ handler: (@Sendable (BackgroundDownloadDriverEvent) -> Void)?
    ) {
        lock.withLock {
            eventHandler = handler
        }
    }

    func attachBackgroundEventsCompletionHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = session

        lock.withLock {
            backgroundEventsCompletionHandler = handler
        }
    }

    func startDownload(
        identifier: String,
        request: URLRequest,
        destination: URL
    ) async throws {
        _ = destination
        let task = session.downloadTask(with: request)
        configure(task, identifier: identifier)
        task.resume()
    }

    func resumeDownload(
        identifier: String,
        request: URLRequest,
        destination: URL,
        resumeData: Data
    ) async throws {
        _ = request
        _ = destination
        let task = session.downloadTask(withResumeData: resumeData)
        configure(task, identifier: identifier)
        task.resume()
    }

    func cancelDownload(
        identifier: String
    ) async throws -> Data? {
        guard let task = lock.withLock({
            tasksByIdentifier[identifier]
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            task.cancel { resumeData in
                continuation.resume(returning: resumeData)
            }
        }
    }

    func restoreActiveDownloads() async throws {
        let tasks = await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }

        tasks
            .compactMap { $0 as? URLSessionDownloadTask }
            .forEach { task in
                guard let identifier = task.taskDescription else {
                    return
                }

                configure(task, identifier: identifier)
            }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        _ = session

        guard let identifier = downloadTask.taskDescription else {
            return
        }

        emit(.progress(
            identifier: identifier,
            bytesWritten: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytesExpectedToWrite
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        _ = session

        guard let identifier = downloadTask.taskDescription else {
            return
        }

        emit(.completed(
            identifier: identifier,
            temporaryFileURL: location,
            response: (downloadTask.response as? HTTPURLResponse).map {
                BackgroundTransferResponse(
                    statusCode: $0.statusCode,
                    headers: $0.allHeaderFields.reduce(into: [:]) { partialResult, item in
                        guard let key = item.key as? String else {
                            return
                        }

                        partialResult[key] = String(describing: item.value)
                    }
                )
            }
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        _ = session

        guard let identifier = task.taskDescription else {
            return
        }

        lock.withLock {
            _ = tasksByIdentifier.removeValue(forKey: identifier)
        }

        guard let error else {
            return
        }

        let resumeData = (error as NSError).userInfo[
            NSURLSessionDownloadTaskResumeData
        ] as? Data

        emit(.failed(
            identifier: identifier,
            reason: .resolve(error: error),
            description: NetworkObservabilitySupport.safeBackgroundFailureDescription(
                reason: .resolve(error: error),
                error: error
            ),
            resumeData: resumeData
        ))
    }

    private func configure(
        _ task: URLSessionDownloadTask,
        identifier: String
    ) {
        task.taskDescription = identifier

        lock.withLock {
            tasksByIdentifier[identifier] = task
        }
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        _ = session

        let completionHandler = lock.withLock {
            defer { backgroundEventsCompletionHandler = nil }
            return backgroundEventsCompletionHandler
        }

        guard let completionHandler else {
            return
        }

        DispatchQueue.main.async(execute: completionHandler)
    }

    private func emit(_ event: BackgroundDownloadDriverEvent) {
        lock.withLock {
            eventHandler?(event)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
