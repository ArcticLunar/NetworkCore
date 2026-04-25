import Alamofire
import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreBackgroundTransferTests: XCTestCase {
    func testFileDownloadResumeStorePersistsLoadsAndRemovesRecords() throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let record = try BackgroundDownloadRecord(
            identifier: "download-1",
            request: makeRequest(url: "https://example.com/file"),
            destinationURL: directoryURL.appendingPathComponent("file.bin"),
            resumeData: Data("resume".utf8)
        )

        try store.save(record)

        let loadedRecord = try store.loadRecord(for: "download-1")
        let allRecords = try store.loadAllRecords()

        XCTAssertEqual(loadedRecord, record)
        XCTAssertEqual(allRecords, [record])

        try store.removeRecord(for: "download-1")

        XCTAssertNil(try store.loadRecord(for: "download-1"))
    }

    func testBackgroundDownloadManagerPersistsPauseResumeAndRestore() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: store,
            driver: driver
        )
        var iterator = manager.events().makeAsyncIterator()
        let request = makeRequest(url: "https://example.com/file")
        let destinationURL = directoryURL.appendingPathComponent("payload.bin")

        let receipt = try await manager.enqueueDownload(
            request: request,
            destination: destinationURL,
            identifier: "download-2"
        )
        let scheduledEvent = await iterator.next()

        XCTAssertEqual(
            scheduledEvent,
            .scheduled(receipt)
        )
        XCTAssertEqual(
            driver.startedIdentifiers(),
            ["download-2"]
        )
        XCTAssertEqual(
            try manager.record(for: "download-2")?.resumeData,
            nil
        )

        driver.setCancelResumeData(Data("resume-data".utf8))
        let pausedRecord = try await manager.pauseDownload(
            identifier: "download-2"
        )
        let pausedEvent = await iterator.next()

        XCTAssertEqual(
            pausedEvent,
            .paused(pausedRecord)
        )
        XCTAssertEqual(
            pausedRecord.resumeData,
            Data("resume-data".utf8)
        )

        let restoredDriver = MockBackgroundDownloadDriver()
        let restoredManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: restoredDriver
        )
        var restoredIterator = restoredManager.events().makeAsyncIterator()

        let restoredRecords = try await restoredManager.restorePersistedDownloads()
        let restoredEvent = await restoredIterator.next()
        XCTAssertEqual(restoredRecords, [pausedRecord])
        XCTAssertEqual(
            restoredEvent,
            .restored(pausedRecord)
        )

        let resumedReceipt = try await restoredManager.resumeDownload(
            identifier: "download-2"
        )
        let resumedEvent = await restoredIterator.next()

        XCTAssertEqual(
            resumedEvent,
            .resumed(resumedReceipt)
        )
        XCTAssertEqual(
            restoredDriver.resumedDownloads(),
            [
                MockBackgroundDownloadDriver.ResumeInvocation(
                    identifier: "download-2",
                    request: pausedRecord.request.makeURLRequest(),
                    destination: destinationURL,
                    resumeData: Data("resume-data".utf8)
                )
            ]
        )
        XCTAssertNil(
            try restoredManager.record(for: "download-2")?.resumeData
        )
    }

    func testBackgroundDownloadManagerRestoreRebindsDriverTasks() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let initialManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: MockBackgroundDownloadDriver()
        )
        let request = makeRequest(url: "https://example.com/file")
        let destinationURL = directoryURL.appendingPathComponent("rebind.bin")

        _ = try await initialManager.enqueueDownload(
            request: request,
            destination: destinationURL,
            identifier: "download-rebind"
        )

        let restoredDriver = MockBackgroundDownloadDriver()
        restoredDriver.setRestorableIdentifiers(["download-rebind"])
        restoredDriver.setCancelResumeData(Data("rebound-resume".utf8))

        let restoredManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: restoredDriver
        )

        _ = try await restoredManager.restorePersistedDownloads()
        let pausedRecord = try await restoredManager.pauseDownload(
            identifier: "download-rebind"
        )

        XCTAssertEqual(restoredDriver.restoreCallCount(), 1)
        XCTAssertEqual(
            pausedRecord.resumeData,
            Data("rebound-resume".utf8)
        )
    }

    func testRestorePersistedDownloadsRehydratesMultipleActiveStatusesAfterRelaunch() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let initialManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: MockBackgroundDownloadDriver()
        )
        let firstDestinationURL = directoryURL.appendingPathComponent("first.bin")
        let secondDestinationURL = directoryURL.appendingPathComponent("second.bin")

        _ = try await initialManager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file/1"),
            destination: firstDestinationURL,
            identifier: "download-restore-1",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext(path: "background/one")
            )
        )
        _ = try await initialManager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file/2"),
            destination: secondDestinationURL,
            identifier: "download-restore-2",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext(path: "background/two")
            )
        )

        let restoredDriver = MockBackgroundDownloadDriver()
        restoredDriver.setRestorableIdentifiers([
            "download-restore-1",
            "download-restore-2"
        ])
        let restoredManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: restoredDriver
        )
        var iterator = restoredManager.statusUpdates().makeAsyncIterator()

        let restoredRecords = try await restoredManager.restorePersistedDownloads()
        let firstStatusValue = await iterator.next()
        let secondStatusValue = await iterator.next()
        let firstStatus = try XCTUnwrap(firstStatusValue)
        let secondStatus = try XCTUnwrap(secondStatusValue)

        XCTAssertEqual(restoredDriver.restoreCallCount(), 1)
        XCTAssertEqual(
            Set(restoredRecords.map(\.identifier)),
            ["download-restore-1", "download-restore-2"]
        )
        XCTAssertEqual(
            Set([firstStatus.identifier, secondStatus.identifier]),
            ["download-restore-1", "download-restore-2"]
        )
        XCTAssertEqual(
            Set(restoredManager.currentStatuses().map(\.identifier)),
            ["download-restore-1", "download-restore-2"]
        )
        XCTAssertEqual(restoredManager.status(for: "download-restore-1")?.path, "background/one")
        XCTAssertEqual(restoredManager.status(for: "download-restore-2")?.path, "background/two")

        guard case .running(nil) = firstStatus.state else {
            return XCTFail("Expected restored running status for first download")
        }
        guard case .running(nil) = secondStatus.state else {
            return XCTFail("Expected restored running status for second download")
        }
    }

    func testBackgroundDownloadManagerPublishesStatusUpdatesAndSupportsStatusQuery() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )
        var iterator = manager.statusUpdates().makeAsyncIterator()
        let request = makeRequest(url: "https://example.com/file")
        let destinationURL = directoryURL.appendingPathComponent("status.bin")
        let context = makeBackgroundTransferContext()

        _ = try await manager.enqueueDownload(
            request: request,
            destination: destinationURL,
            identifier: "download-status",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: context
            )
        )

        let pendingStatusValue = await iterator.next()
        let pendingStatus = try XCTUnwrap(pendingStatusValue)
        XCTAssertEqual(pendingStatus.identifier, "download-status")
        XCTAssertEqual(pendingStatus.requestID, context.requestID)
        XCTAssertEqual(pendingStatus.environmentName, "test")
        XCTAssertEqual(pendingStatus.method, .get)
        XCTAssertEqual(pendingStatus.path, "background")
        XCTAssertEqual(pendingStatus.destinationURL, destinationURL)
        XCTAssertEqual(pendingStatus.state, .pending)
        XCTAssertEqual(
            manager.status(for: "download-status")?.state,
            .pending
        )
        XCTAssertEqual(
            manager.currentStatuses().map(\.identifier),
            ["download-status"]
        )

        driver.emit(.progress(
            identifier: "download-status",
            bytesWritten: 16,
            totalBytesWritten: 48,
            totalBytesExpected: 96
        ))

        let runningStatusValue = await iterator.next()
        let runningStatus = try XCTUnwrap(runningStatusValue)
        guard case let .running(progress?) = runningStatus.state else {
            return XCTFail("Expected running status")
        }
        XCTAssertEqual(progress.bytesWritten, 16)
        XCTAssertEqual(progress.totalBytesWritten, 48)
        XCTAssertEqual(progress.totalBytesExpected, 96)
        XCTAssertEqual(progress.fractionCompleted, 0.5)
        XCTAssertEqual(
            manager.status(for: "download-status")?.state,
            runningStatus.state
        )

        let temporaryFileURL = directoryURL.appendingPathComponent("status-temp.bin")
        try Data("payload".utf8).write(to: temporaryFileURL)

        driver.emit(.completed(
            identifier: "download-status",
            temporaryFileURL: temporaryFileURL,
            response: BackgroundTransferResponse(
                statusCode: 200,
                headers: ["ETag": "status"]
            )
        ))

        let completedStatusValue = await iterator.next()
        let completedStatus = try XCTUnwrap(completedStatusValue)
        guard case let .completed(response?) = completedStatus.state else {
            return XCTFail("Expected completed status")
        }
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNil(manager.status(for: "download-status"))
        XCTAssertTrue(manager.currentStatuses().isEmpty)
    }

    func testBackgroundDownloadManagerTreatsHTTPFailureAsFailedStatusAndKeepsRecordForRetry() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )
        var iterator = manager.statusUpdates().makeAsyncIterator()
        let destinationURL = directoryURL.appendingPathComponent("http-failure.bin")

        _ = try await manager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file"),
            destination: destinationURL,
            identifier: "download-http-failure",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        _ = await iterator.next()

        let temporaryFileURL = directoryURL.appendingPathComponent("http-failure-temp.bin")
        try Data("server-error".utf8).write(to: temporaryFileURL)

        driver.emit(.completed(
            identifier: "download-http-failure",
            temporaryFileURL: temporaryFileURL,
            response: BackgroundTransferResponse(
                statusCode: 503,
                headers: ["Retry-After": "60"]
            )
        ))

        let failedStatusValue = await iterator.next()
        let failedStatus = try XCTUnwrap(failedStatusValue)

        guard case let .failed(reason, _, resumeDataAvailable) = failedStatus.state else {
            return XCTFail("Expected failed status")
        }

        XCTAssertEqual(reason, .httpStatus(code: 503))
        XCTAssertFalse(resumeDataAvailable)
        XCTAssertEqual(
            try manager.record(for: "download-http-failure")?.destinationURL,
            destinationURL
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temporaryFileURL.path)
        )
        XCTAssertEqual(
            manager.status(for: "download-http-failure")?.state,
            failedStatus.state
        )
    }

    func testBackgroundDownloadManagerSanitizesFailureStatusDescription() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )
        var iterator = manager.statusUpdates().makeAsyncIterator()

        _ = try await manager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file"),
            destination: directoryURL.appendingPathComponent("sanitized.bin"),
            identifier: "download-sanitized",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        _ = await iterator.next()

        driver.emit(.failed(
            identifier: "download-sanitized",
            reason: .offline,
            description: "token=secret network dropped",
            resumeData: nil
        ))

        let failedStatusValue = await iterator.next()
        let failedStatus = try XCTUnwrap(failedStatusValue)

        guard case let .failed(reason, description, resumeDataAvailable) = failedStatus.state else {
            return XCTFail("Expected failed status")
        }

        XCTAssertEqual(reason, .offline)
        XCTAssertFalse(resumeDataAvailable)
        XCTAssertEqual(description, "reason=offline")
        XCTAssertFalse(description.contains("secret"))
        XCTAssertFalse(description.contains("network dropped"))
    }

    func testBackgroundDownloadManagerCanRestartFailedDownloadWithoutResumeData() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )
        let destinationURL = directoryURL.appendingPathComponent("restart.bin")

        _ = try await manager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file"),
            destination: destinationURL,
            identifier: "download-restart",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        driver.emit(.failed(
            identifier: "download-restart",
            reason: .offline,
            description: "offline",
            resumeData: nil
        ))

        _ = try await manager.resumeDownload(identifier: "download-restart")

        XCTAssertEqual(
            driver.startedIdentifiers(),
            ["download-restart", "download-restart"]
        )
    }

    func testRestorePersistedDownloadsPublishesPausedStatusSnapshotForPausedRecord() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let initialDriver = MockBackgroundDownloadDriver()
        let initialManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: initialDriver
        )
        let destinationURL = directoryURL.appendingPathComponent("paused.bin")

        _ = try await initialManager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file"),
            destination: destinationURL,
            identifier: "download-paused-status",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )
        initialDriver.setCancelResumeData(Data("resume".utf8))
        _ = try await initialManager.pauseDownload(
            identifier: "download-paused-status"
        )

        let restoredManager = BackgroundDownloadManager(
            resumeStore: store,
            driver: MockBackgroundDownloadDriver()
        )
        var iterator = restoredManager.statusUpdates().makeAsyncIterator()

        _ = try await restoredManager.restorePersistedDownloads()

        let restoredStatusValue = await iterator.next()
        let restoredStatus = try XCTUnwrap(restoredStatusValue)
        XCTAssertEqual(restoredStatus.identifier, "download-paused-status")
        XCTAssertEqual(restoredStatus.destinationURL, destinationURL)
        XCTAssertEqual(
            restoredStatus.state,
            .paused(resumeDataAvailable: true)
        )
        XCTAssertEqual(
            restoredManager.status(for: "download-paused-status")?.state,
            .paused(resumeDataAvailable: true)
        )
        XCTAssertEqual(
            restoredManager.currentStatuses().map(\.identifier),
            ["download-paused-status"]
        )
    }

    func testBackgroundDownloadManagerHandlesSystemBackgroundEvents() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let restoreExpectation = expectation(description: "restore invoked")
        let completionExpectation = expectation(
            description: "background completion handler called"
        )
        let driver = MockBackgroundDownloadDriver(
            sessionIdentifier: "system-events-direct"
        )
        driver.setOnRestore {
            restoreExpectation.fulfill()
        }

        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )

        manager.handleEventsForBackgroundURLSession {
            completionExpectation.fulfill()
        }

        await fulfillment(of: [restoreExpectation], timeout: 1.0)
        XCTAssertEqual(
            driver.attachedBackgroundCompletionHandlerCount(),
            1
        )

        driver.finishBackgroundEvents()
        await fulfillment(of: [completionExpectation], timeout: 1.0)
    }

    func testBackgroundTransferSystemCoordinatorDeliversPendingCompletionHandlerWhenManagerRegisters() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sessionIdentifier = "system-events-pending-\(UUID().uuidString)"
        let restoreExpectation = expectation(description: "pending restore invoked")
        let completionExpectation = expectation(
            description: "pending background completion handler called"
        )

        BackgroundTransferSystemCoordinator.shared.handleEvents(
            forBackgroundURLSession: sessionIdentifier
        ) {
            completionExpectation.fulfill()
        }

        let driver = MockBackgroundDownloadDriver(
            sessionIdentifier: sessionIdentifier
        )
        driver.setOnRestore {
            restoreExpectation.fulfill()
        }

        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver
        )
        _ = manager

        await fulfillment(of: [restoreExpectation], timeout: 1.0)
        XCTAssertEqual(
            driver.attachedBackgroundCompletionHandlerCount(),
            1
        )

        driver.finishBackgroundEvents()
        await fulfillment(of: [completionExpectation], timeout: 1.0)
    }

    func testBackgroundDownloadManagerCompletesAndRemovesPersistedRecord() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileDownloadResumeStore(directoryURL: directoryURL)
        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: store,
            driver: driver
        )
        var iterator = manager.events().makeAsyncIterator()
        let destinationURL = directoryURL.appendingPathComponent("completed.bin")

        let receipt = try await manager.enqueueDownload(
            request: makeRequest(url: "https://example.com/file"),
            destination: destinationURL,
            identifier: "download-3"
        )
        let scheduledEvent = await iterator.next()

        XCTAssertEqual(scheduledEvent, .scheduled(receipt))

        let temporaryFileURL = directoryURL.appendingPathComponent("temp.bin")
        try Data("payload".utf8).write(to: temporaryFileURL)

        driver.emit(.completed(
            identifier: "download-3",
            temporaryFileURL: temporaryFileURL,
            response: BackgroundTransferResponse(
                statusCode: 200,
                headers: ["ETag": "bolt"]
            )
        ))
        let completedEvent = await iterator.next()

        XCTAssertEqual(
            completedEvent,
            .completed(
                receipt: receipt,
                response: BackgroundTransferResponse(
                    statusCode: 200,
                    headers: ["ETag": "bolt"]
                )
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            Data("payload".utf8)
        )
        XCTAssertNil(try manager.record(for: "download-3"))
    }

    func testAlamofireTransportReturnsBackgroundTransferReceipt() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: MockBackgroundDownloadDriver()
        )
        let transport = AlamofireTransport(
            session: Session(configuration: .ephemeral),
            backgroundDownloadManager: manager
        )
        let destinationURL = directoryURL.appendingPathComponent("transport.bin")
        let context = makeBackgroundTransferContext()
        let response = try await transport.send(
            TransportRequest(
                urlRequest: makeRequest(url: "https://example.com/file"),
                task: .backgroundDownload(
                    destination: destinationURL,
                    transferIdentifier: "download-4"
                )
            ),
            context: context,
            progressHandler: nil
        )

        XCTAssertEqual(response.response.statusCode, 202)
        XCTAssertEqual(
            response.backgroundTransferReceipt,
            BackgroundTransferReceipt(
                identifier: "download-4",
                destinationURL: destinationURL
            )
        )
        XCTAssertNil(response.downloadedFileURL)
        XCTAssertTrue(response.data.isEmpty)
        XCTAssertEqual(
            try manager.record(for: "download-4")?.destinationURL,
            destinationURL
        )
        XCTAssertEqual(
            try manager.record(for: "download-4")?.observability,
            BackgroundDownloadRecord.ObservabilitySnapshot(
                context: context
            )
        )
    }

    func testBackgroundTransferMetricsObserverRecordsProgressCompletionAndFailure() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sink = RecordingBackgroundMetricsSink()
        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver,
            observers: [
                BackgroundTransferMetricsObserver(sink: sink)
            ]
        )
        let request = makeRequest(url: "https://example.com/file")
        let destinationURL = directoryURL.appendingPathComponent("metrics.bin")

        let receipt = try await manager.enqueueDownload(
            request: request,
            destination: destinationURL,
            identifier: "download-metrics",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        driver.emit(.progress(
            identifier: "download-metrics",
            bytesWritten: 32,
            totalBytesWritten: 64,
            totalBytesExpected: 128
        ))

        let temporaryFileURL = directoryURL.appendingPathComponent("metrics-temp.bin")
        try Data("payload".utf8).write(to: temporaryFileURL)

        driver.emit(.completed(
            identifier: "download-metrics",
            temporaryFileURL: temporaryFileURL,
            response: BackgroundTransferResponse(
                statusCode: 206,
                headers: ["ETag": "metrics"]
            )
        ))

        let failedReceipt = try await manager.enqueueDownload(
            request: request,
            destination: directoryURL.appendingPathComponent("failed.bin"),
            identifier: "download-failure",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        XCTAssertEqual(receipt.identifier, "download-metrics")
        XCTAssertEqual(failedReceipt.identifier, "download-failure")

        driver.emit(.failed(
            identifier: "download-failure",
            reason: .offline,
            description: "network dropped",
            resumeData: Data("resume".utf8)
        ))

        let snapshot = sink.snapshot()

        XCTAssertTrue(
            snapshot.counter(named: "network.background_transfer.scheduled.count").isEmpty == false
        )
        XCTAssertTrue(
            snapshot.counter(named: "network.background_transfer.progress.count").isEmpty == false
        )
        XCTAssertTrue(
            snapshot.counter(named: "network.background_transfer.completed.count").isEmpty == false
        )
        XCTAssertTrue(
            snapshot.counter(named: "network.background_transfer.failed.count").isEmpty == false
        )
        XCTAssertEqual(
            snapshot.counter(named: "network.background_transfer.completed.count").last?.dimensions["status_code"],
            "206"
        )
        XCTAssertEqual(
            snapshot.counter(named: "network.background_transfer.failed.count").last?.dimensions["resume_data_available"],
            "true"
        )
        XCTAssertEqual(
            snapshot.counter(named: "network.background_transfer.failed.count").last?.dimensions["failure_reason"],
            "offline"
        )
        XCTAssertEqual(
            snapshot.counter(named: "network.background_transfer.progress.count").last?.dimensions["environment"],
            "test"
        )
        XCTAssertEqual(
            snapshot.counter(named: "network.background_transfer.progress.count").last?.dimensions["path"],
            "background"
        )
        XCTAssertEqual(snapshot.latencies.count, 2)
    }

    func testBackgroundTransferLoggerObserverLogsStructuredRecordsAndRedactsHeaders() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sink = RecordingBackgroundLogSink()
        let driver = MockBackgroundDownloadDriver()
        let manager = BackgroundDownloadManager(
            resumeStore: FileDownloadResumeStore(directoryURL: directoryURL),
            driver: driver,
            observers: [
                BackgroundTransferLoggerObserver(
                    sink: sink,
                    redactor: DefaultNetworkRedactor()
                )
            ]
        )
        let request = makeRequest(url: "https://example.com/file")
        let destinationURL = directoryURL.appendingPathComponent("logger.bin")

        let receipt = try await manager.enqueueDownload(
            request: request,
            destination: destinationURL,
            identifier: "download-logger",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )

        driver.emit(.progress(
            identifier: "download-logger",
            bytesWritten: 16,
            totalBytesWritten: 32,
            totalBytesExpected: 64
        ))

        let temporaryFileURL = directoryURL.appendingPathComponent("logger-temp.bin")
        try Data("payload".utf8).write(to: temporaryFileURL)

        driver.emit(.completed(
            identifier: "download-logger",
            temporaryFileURL: temporaryFileURL,
            response: BackgroundTransferResponse(
                statusCode: 206,
                headers: [
                    "Content-Type": "application/octet-stream",
                    "Set-Cookie": "secret"
                ]
            )
        ))

        _ = try await manager.enqueueDownload(
            request: request,
            destination: directoryURL.appendingPathComponent("logger-failed.bin"),
            identifier: "download-logger-failure",
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: makeBackgroundTransferContext()
            )
        )
        driver.emit(.failed(
            identifier: "download-logger-failure",
            reason: .offline,
            description: "network dropped",
            resumeData: Data("resume".utf8)
        ))

        XCTAssertEqual(receipt.identifier, "download-logger")

        let records = sink.snapshot()
        XCTAssertEqual(
            records.map(\.phase),
            [
                .backgroundScheduled,
                .backgroundProgress,
                .backgroundCompleted,
                .backgroundScheduled,
                .backgroundFailed
            ]
        )
        XCTAssertEqual(
            records.first?.requestHeaders?["Authorization"],
            "<redacted>"
        )
        XCTAssertEqual(
            records[1].attributes?["identifier"],
            "download-logger"
        )
        XCTAssertEqual(
            records[1].attributes?["total_bytes_written"],
            "32"
        )
        XCTAssertEqual(
            records[2].statusCode,
            206
        )
        XCTAssertEqual(
            records[2].responseHeaders?["Set-Cookie"],
            "<redacted>"
        )
        XCTAssertEqual(
            records[4].phase,
            .backgroundFailed
        )
        XCTAssertEqual(
            records[4].attributes?["resume_data_available"],
            "true"
        )
        XCTAssertEqual(
            records[4].attributes?["failure_reason"],
            "offline"
        )
        XCTAssertEqual(
            records[4].errorCategory,
            "background_transfer_failed"
        )
        XCTAssertEqual(
            records[4].errorDescription,
            "reason=offline"
        )
    }

    @MainActor
    private func waitUntil(
        description: String,
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Timed out waiting for \(description)")
    }

    private func temporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private func makeRequest(url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = NetworkCore.HTTPMethod.get.rawValue
        request.setValue("Bearer bolt", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }
}

private final class MockBackgroundDownloadDriver:
    BackgroundDownloadDriving,
    @unchecked Sendable {

    struct ResumeInvocation: Equatable {
        let identifier: String
        let request: URLRequest
        let destination: URL
        let resumeData: Data

        static func == (lhs: ResumeInvocation, rhs: ResumeInvocation) -> Bool {
            lhs.identifier == rhs.identifier
                && lhs.request.url == rhs.request.url
                && lhs.request.httpMethod == rhs.request.httpMethod
                && lhs.request.allHTTPHeaderFields == rhs.request.allHTTPHeaderFields
                && lhs.destination == rhs.destination
                && lhs.resumeData == rhs.resumeData
        }
    }

    private let lock = NSLock()
    let sessionIdentifier: String
    private var eventHandler: (@Sendable (BackgroundDownloadDriverEvent) -> Void)?
    private var backgroundEventsCompletionHandler: (() -> Void)?
    private var started: [String] = []
    private var resumed: [ResumeInvocation] = []
    private var cancelResumeData: Data?
    private var activeIdentifiers: Set<String> = []
    private var restorableIdentifiers: Set<String> = []
    private var restoreInvocations = 0
    private var attachedCompletionHandlerInvocations = 0
    private var onRestore: (() -> Void)?

    init(sessionIdentifier: String = UUID().uuidString) {
        self.sessionIdentifier = sessionIdentifier
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
        lock.withLock {
            backgroundEventsCompletionHandler = handler
            attachedCompletionHandlerInvocations += 1
        }
    }

    func startDownload(
        identifier: String,
        request: URLRequest,
        destination: URL
    ) async throws {
        _ = request
        _ = destination

        lock.withLock {
            started.append(identifier)
            activeIdentifiers.insert(identifier)
        }
    }

    func resumeDownload(
        identifier: String,
        request: URLRequest,
        destination: URL,
        resumeData: Data
    ) async throws {
        lock.withLock {
            resumed.append(
                ResumeInvocation(
                    identifier: identifier,
                    request: request,
                    destination: destination,
                    resumeData: resumeData
                )
            )
            activeIdentifiers.insert(identifier)
        }
    }

    func cancelDownload(
        identifier: String
    ) async throws -> Data? {
        return lock.withLock {
            guard activeIdentifiers.contains(identifier) else {
                return nil
            }

            activeIdentifiers.remove(identifier)
            return cancelResumeData
        }
    }

    func restoreActiveDownloads() async throws {
        let onRestore = lock.withLock {
            restoreInvocations += 1
            activeIdentifiers.formUnion(restorableIdentifiers)
            return self.onRestore
        }

        onRestore?()
    }

    func setOnRestore(_ onRestore: (() -> Void)?) {
        lock.withLock {
            self.onRestore = onRestore
        }
    }

    func setCancelResumeData(_ data: Data?) {
        lock.withLock {
            cancelResumeData = data
        }
    }

    func setRestorableIdentifiers(_ identifiers: Set<String>) {
        lock.withLock {
            restorableIdentifiers = identifiers
        }
    }

    func emit(_ event: BackgroundDownloadDriverEvent) {
        lock.withLock {
            eventHandler?(event)
        }
    }

    func finishBackgroundEvents() {
        let completionHandler = lock.withLock {
            defer { backgroundEventsCompletionHandler = nil }
            return backgroundEventsCompletionHandler
        }

        completionHandler?()
    }

    func startedIdentifiers() -> [String] {
        lock.withLock {
            started
        }
    }

    func resumedDownloads() -> [ResumeInvocation] {
        lock.withLock {
            resumed
        }
    }

    func restoreCallCount() -> Int {
        lock.withLock {
            restoreInvocations
        }
    }

    func attachedBackgroundCompletionHandlerCount() -> Int {
        lock.withLock {
            attachedCompletionHandlerInvocations
        }
    }
}

private final class RecordingBackgroundMetricsSink: NetworkMetricsSink {
    struct CounterRecord {
        let name: String
        let dimensions: [String: String]
    }

    struct LatencyRecord {
        let name: String
        let duration: TimeInterval
        let dimensions: [String: String]
    }

    struct Snapshot {
        let counters: [CounterRecord]
        let latencies: [LatencyRecord]

        func counter(named name: String) -> [CounterRecord] {
            counters.filter { $0.name == name }
        }
    }

    private let lock = NSLock()
    private var counters: [CounterRecord] = []
    private var latencies: [LatencyRecord] = []

    func incrementCounter(_ name: String, dimensions: [String: String]) {
        lock.withLock {
            counters.append(
                CounterRecord(
                    name: name,
                    dimensions: dimensions
                )
            )
        }
    }

    func recordLatency(_ name: String, duration: TimeInterval, dimensions: [String: String]) {
        lock.withLock {
            latencies.append(
                LatencyRecord(
                    name: name,
                    duration: duration,
                    dimensions: dimensions
                )
            )
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                counters: counters,
                latencies: latencies
            )
        }
    }
}

private final class RecordingBackgroundLogSink: NetworkLogSink {
    private let lock = NSLock()
    private var records: [NetworkLogRecord] = []

    func log(_ record: NetworkLogRecord) {
        lock.withLock {
            records.append(record)
        }
    }

    func snapshot() -> [NetworkLogRecord] {
        lock.withLock {
            records
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

private func makeBackgroundTransferContext() -> NetworkRequestContext {
    makeBackgroundTransferContext(path: "background")
}

private func makeBackgroundTransferContext(path: String) -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: path,
        method: NetworkCore.HTTPMethod.get,
        authorization: .none,
        options: .default
    )
}
