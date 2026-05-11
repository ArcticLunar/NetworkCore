// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Alamofire
import Foundation
import XCTest
@testable import NetworkCore

final class NetworkCoreTransportTests: XCTestCase {
    func testTransportResponseReturnsInMemoryBodyForRegularResponse() throws {
        let response = try makeTransportResponse(
            path: "payload",
            statusCode: 200,
            data: Data("bolt".utf8)
        )

        XCTAssertNil(response.downloadedFileURL)
        XCTAssertEqual(response.data, Data("bolt".utf8))
        XCTAssertEqual(try response.loadData(), Data("bolt".utf8))
    }

    func testTransportResponseLoadsDownloadedFileDataLazily() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let fileURL = tempDirectory.appendingPathComponent("payload.bin")
        let expectedData = Data("bolt-download".utf8)
        try expectedData.write(to: fileURL)

        let request = URLRequest(url: URL(string: "https://example.com/file")!)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        let transportResponse = TransportResponse(
            request: request,
            response: response,
            data: Data(),
            downloadedFileURL: fileURL
        )

        XCTAssertEqual(transportResponse.downloadedFileURL, fileURL)
        XCTAssertTrue(transportResponse.data.isEmpty)
        XCTAssertEqual(try transportResponse.loadData(), expectedData)
    }

    func testRequestDataInvokesUploadProgressHandler() async throws {
        let transport = ProgressEmittingTransport()
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )
        let progressExpectation = expectation(description: "upload progress")
        progressExpectation.expectedFulfillmentCount = 2
        let recorder = ProgressRecorder()

        _ = try await client.requestData(
            UploadProgressEndpoint(),
            progressHandler: TransportProgressHandler(
                upload: { progress in
                    recorder.record(progress)
                    progressExpectation.fulfill()
                }
            )
        )

        await fulfillment(of: [progressExpectation], timeout: 1)
        XCTAssertEqual(recorder.completedUnitCounts, [50, 100])
    }

    func testRequestDataInvokesDownloadProgressHandler() async throws {
        let transport = ProgressEmittingTransport()
        let client = NetworkClient(
            configuration: makeConfiguration(
                retryPolicies: []
            ),
            transport: transport
        )
        let progressExpectation = expectation(description: "download progress")
        progressExpectation.expectedFulfillmentCount = 2
        let recorder = ProgressRecorder()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let response = try await client.requestData(
            DownloadProgressEndpoint(
                destination: tempDirectory.appendingPathComponent("payload.bin")
            ),
            progressHandler: TransportProgressHandler(
                download: { progress in
                    recorder.record(progress)
                    progressExpectation.fulfill()
                }
            )
        )

        await fulfillment(of: [progressExpectation], timeout: 1)
        XCTAssertEqual(recorder.completedUnitCounts, [40, 100])
        XCTAssertEqual(try response.loadData(), Data("downloaded-payload".utf8))
    }

    func testAlamofireTransportMapsTaskCancellationToCancelled() async throws {
        let startExpectation = expectation(description: "request started")
        let stopExpectation = expectation(description: "request stopped")
        SlowURLProtocol.configure(
            startExpectation: startExpectation,
            stopExpectation: stopExpectation
        )
        defer {
            SlowURLProtocol.reset()
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowURLProtocol.self]

        let transport = AlamofireTransport(
            session: Session(configuration: configuration)
        )
        let request = TransportRequest(
            urlRequest: URLRequest(url: URL(string: "https://example.com/slow")!),
            task: .request
        )

        let task = Task {
            try await transport.send(
                request,
                context: makeTransportContext(),
                progressHandler: nil
            )
        }

        await fulfillment(of: [startExpectation], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            guard case .cancelled = ErrorMapper.map(error) else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [stopExpectation], timeout: 1)
    }
}

private actor ProgressEmittingTransport: NetworkTransport {
    func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        switch request.task {
        case .request:
            return try makeResponse(
                request: request.urlRequest,
                data: Data(#"{"ok":true}"#.utf8)
            )

        case .upload:
            progressHandler?.upload?(makeProgress(total: 100, completed: 50))
            progressHandler?.upload?(makeProgress(total: 100, completed: 100))
            return try makeResponse(
                request: request.urlRequest,
                data: Data()
            )

        case let .download(destination):
            progressHandler?.download?(makeProgress(total: 100, completed: 40))
            progressHandler?.download?(makeProgress(total: 100, completed: 100))

            let data = Data("downloaded-payload".utf8)
            try data.write(to: destination)

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.urlRequest.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )

            return TransportResponse(
                request: request.urlRequest,
                response: response,
                data: Data(),
                downloadedFileURL: destination
            )

        case let .backgroundDownload(destination, transferIdentifier):
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.urlRequest.url!,
                    statusCode: 202,
                    httpVersion: nil,
                    headerFields: nil
                )
            )

            return TransportResponse(
                request: request.urlRequest,
                response: response,
                data: Data(),
                backgroundTransferReceipt: BackgroundTransferReceipt(
                    identifier: transferIdentifier ?? "background-test",
                    destinationURL: destination
                )
            )
        }
    }

    private func makeResponse(
        request: URLRequest,
        data: Data
    ) throws -> TransportResponse {
        let headers = data.isEmpty ? nil : ["Content-Type": "application/json"]
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )
        )

        return TransportResponse(
            request: request,
            response: response,
            data: data
        )
    }

    private func makeProgress(total: Int64, completed: Int64) -> Progress {
        let progress = Progress(totalUnitCount: total)
        progress.completedUnitCount = completed
        return progress
    }
}

private final class ProgressRecorder {
    private let lock = NSLock()
    private var values: [Int64] = []

    var completedUnitCounts: [Int64] {
        lock.withLock { values }
    }

    func record(_ progress: Progress) {
        lock.withLock {
            values.append(progress.completedUnitCount)
        }
    }
}

private struct UploadProgressEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let path = "upload"
    let method: NetworkCore.HTTPMethod = .post
    let task: RequestTask = .upload(
        data: Data("upload-payload".utf8),
        contentType: "application/octet-stream"
    )
}

private struct DownloadProgressEndpoint: APIEndpoint {
    typealias Response = NetworkCore.EmptyResponse

    let destination: URL

    let path = "download"
    let method: NetworkCore.HTTPMethod = .get

    var task: RequestTask {
        .download(destination: destination)
    }
}

private final class SlowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var startExpectation: XCTestExpectation?
    private static var stopExpectation: XCTestExpectation?

    private var responseTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.startExpectation?.fulfill()
        }

        responseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            guard let self, Task.isCancelled == false else {
                return
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        responseTask?.cancel()
        Self.lock.withLock {
            Self.stopExpectation?.fulfill()
        }
    }

    static func configure(
        startExpectation: XCTestExpectation,
        stopExpectation: XCTestExpectation
    ) {
        lock.withLock {
            self.startExpectation = startExpectation
            self.stopExpectation = stopExpectation
        }
    }

    static func reset() {
        lock.withLock {
            startExpectation = nil
            stopExpectation = nil
        }
    }
}

private func makeTransportContext() -> NetworkRequestContext {
    NetworkRequestContext(
        environmentName: "test",
        path: "transport",
        method: NetworkCore.HTTPMethod.get,
        authorization: .none,
        options: .default
    )
}
