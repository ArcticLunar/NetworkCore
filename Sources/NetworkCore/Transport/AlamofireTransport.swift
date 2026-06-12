// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 使用 Alamofire 执行普通请求、上传、前台下载和后台下载排队。

import Alamofire
import Foundation

/// 基于 Alamofire 的默认 transport 实现。
public final class AlamofireTransport: NetworkTransport, @unchecked Sendable {
    private enum TransportInternalError: Error {
        case missingHTTPResponse
        case missingDownloadedFile
    }

    private let session: Session
    private let backgroundDownloadManager: BackgroundDownloadManager?

    public init(
        session: Session,
        backgroundDownloadManager: BackgroundDownloadManager? = nil
    ) {
        self.session = session
        self.backgroundDownloadManager = backgroundDownloadManager
    }

    public func send(
        _ request: TransportRequest,
        context: NetworkRequestContext,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        do {
            switch request.task {
            case .request:
                return try await performRequest(
                    request.urlRequest,
                    progressHandler: progressHandler
                )

            case let .upload(data):
                return try await performUpload(
                    request.urlRequest,
                    data: data,
                    progressHandler: progressHandler
                )

            case let .download(destination):
                return try await performDownload(
                    request.urlRequest,
                    destination: destination,
                    progressHandler: progressHandler
                )

            case let .backgroundDownload(destination, transferIdentifier):
                return try await performBackgroundDownload(
                    request.urlRequest,
                    destination: destination,
                    transferIdentifier: transferIdentifier,
                    context: context
                )
            }
        } catch let error as NetworkError {
            throw error
        } catch is TransportInternalError {
            throw NetworkError.invalidResponse
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as AFError {
            throw map(error)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private func performRequest(
        _ request: URLRequest,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        let dataRequest = session.request(request)
        observeProgress(
            of: dataRequest,
            progressHandler: progressHandler
        )

        let response = await dataRequest.serializingData().response
        return try makeTransportResponse(request: request, response: response)
    }

    private func performUpload(
        _ request: URLRequest,
        data: Data,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        let uploadRequest = session.upload(data, with: request)
        observeProgress(
            of: uploadRequest,
            progressHandler: progressHandler
        )

        let response = await uploadRequest.serializingData().response
        return try makeTransportResponse(request: request, response: response)
    }

    private func performDownload(
        _ request: URLRequest,
        destination: URL,
        progressHandler: TransportProgressHandler?
    ) async throws -> TransportResponse {
        let target: DownloadRequest.Destination = { _, _ in
            (destination, [.removePreviousFile, .createIntermediateDirectories])
        }

        let downloadRequest = session.download(request, to: target)
        observeProgress(
            of: downloadRequest,
            progressHandler: progressHandler
        )

        let response = await downloadRequest.serializingDownloadedFileURL().response

        if let error = response.error {
            throw error
        }

        guard let httpResponse = response.response else {
            throw TransportInternalError.missingHTTPResponse
        }

        guard let fileURL = response.value else {
            throw TransportInternalError.missingDownloadedFile
        }

        return TransportResponse(
            request: request,
            response: httpResponse,
            data: Data(),
            downloadedFileURL: fileURL
        )
    }

    private func performBackgroundDownload(
        _ request: URLRequest,
        destination: URL,
        transferIdentifier: String?,
        context: NetworkRequestContext
    ) async throws -> TransportResponse {
        guard let backgroundDownloadManager else {
            throw NetworkError.invalidRequest(
                "Background download manager is not configured"
            )
        }

        let receipt = try await backgroundDownloadManager.enqueueDownload(
            request: request,
            destination: destination,
            identifier: transferIdentifier,
            observability: BackgroundDownloadRecord.ObservabilitySnapshot(
                context: context
            )
        )
        // 后台下载是异步排队语义，这里返回 202 表示任务已被接受，真实完成状态
        // 通过 BackgroundDownloadManager 的事件流继续通知。
        let acceptedResponse = try makeAcceptedResponse(for: request)

        return TransportResponse(
            request: request,
            response: acceptedResponse,
            data: Data(),
            backgroundTransferReceipt: receipt
        )
    }

    private func makeTransportResponse(
        request: URLRequest,
        response: AFDataResponse<Data>
    ) throws -> TransportResponse {
        if let error = response.error {
            throw error
        }

        guard let httpResponse = response.response else {
            throw TransportInternalError.missingHTTPResponse
        }

        return TransportResponse(
            request: request,
            response: httpResponse,
            data: response.data ?? Data()
        )
    }

    private func makeAcceptedResponse(
        for request: URLRequest
    ) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
              ) else {
            throw NetworkError.invalidResponse
        }

        return response
    }

    private func map(_ error: AFError) -> NetworkError {
        if error.isExplicitlyCancelledError {
            return .cancelled
        }

        if case .serverTrustEvaluationFailed = error {
            return .serverTrustFailure(underlying: error)
        }

        if let urlError = error.underlyingError as? URLError {
            return ErrorMapper.map(urlError)
        }

        return .transport(underlying: error)
    }

    private func observeProgress(
        of request: Request,
        progressHandler: TransportProgressHandler?
    ) {
        if let upload = progressHandler?.upload {
            request.uploadProgress(queue: .main, closure: upload)
        }

        if let download = progressHandler?.download {
            request.downloadProgress(queue: .main, closure: download)
        }
    }
}
