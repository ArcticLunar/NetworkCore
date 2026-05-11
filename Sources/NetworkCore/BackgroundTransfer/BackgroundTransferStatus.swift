// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct BackgroundTransferProgress: Equatable, Sendable {
    public let bytesWritten: Int64
    public let totalBytesWritten: Int64
    public let totalBytesExpected: Int64?

    public init(
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64?
    ) {
        self.bytesWritten = bytesWritten
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpected = totalBytesExpected
    }

    public var fractionCompleted: Double? {
        guard let totalBytesExpected,
              totalBytesExpected > 0 else {
            return nil
        }

        return Double(totalBytesWritten) / Double(totalBytesExpected)
    }
}

public enum BackgroundTransferFailureReason: Equatable, Sendable {
    case cancelled
    case offline
    case networkLost
    case timeout
    case dnsFailure
    case cannotConnect
    case tlsFailure
    case serverTrustFailure
    case unauthorized(statusCode: Int?)
    case httpStatus(code: Int)
    case fileSystem
    case networkAccessRestricted
    case transport
    case unknown
}

public enum BackgroundTransferState: Equatable, Sendable {
    case pending
    case running(BackgroundTransferProgress?)
    case paused(resumeDataAvailable: Bool)
    case failed(
        reason: BackgroundTransferFailureReason,
        description: String,
        resumeDataAvailable: Bool
    )
    case completed(response: BackgroundTransferResponse?)
}

public struct BackgroundTransferStatus: Equatable, Sendable {
    public let identifier: String
    public let requestID: String?
    public let environmentName: String?
    public let method: HTTPMethod?
    public let path: String?
    public let destinationURL: URL?
    public let createdAt: Date?
    public let updatedAt: Date
    public let state: BackgroundTransferState

    public init(
        identifier: String,
        requestID: String? = nil,
        environmentName: String? = nil,
        method: HTTPMethod? = nil,
        path: String? = nil,
        destinationURL: URL? = nil,
        createdAt: Date? = nil,
        updatedAt: Date = Date(),
        state: BackgroundTransferState
    ) {
        self.identifier = identifier
        self.requestID = requestID
        self.environmentName = environmentName
        self.method = method
        self.path = path
        self.destinationURL = destinationURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
    }
}

public extension BackgroundTransferFailureReason {
    static func resolve(error: Error) -> BackgroundTransferFailureReason {
        if let failure = error as? NetworkFailure {
            return resolve(networkError: failure.error)
        }

        if let error = error as? NetworkError {
            return resolve(networkError: error)
        }

        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            return .fileSystem
        }

        guard nsError.domain == NSURLErrorDomain else {
            return .transport
        }

        let code = URLError.Code(rawValue: nsError.code)

        switch code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet:
            return .offline
        case .networkConnectionLost:
            return .networkLost
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure
        case .cannotConnectToHost:
            return .cannotConnect
        case .secureConnectionFailed:
            return .tlsFailure
        case .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .serverTrustFailure
        default:
            return .transport
        }
    }

    static func resolve(networkError: NetworkError) -> BackgroundTransferFailureReason {
        switch networkError {
        case .offline:
            return .offline
        case .timeout:
            return .timeout
        case .cancelled:
            return .cancelled
        case .dnsFailure:
            return .dnsFailure
        case .cannotConnect:
            return .cannotConnect
        case .tlsFailure:
            return .tlsFailure
        case .serverTrustFailure:
            return .serverTrustFailure
        case .networkAccessRestricted:
            return .networkAccessRestricted
        case let .httpStatus(code, _):
            return resolve(statusCode: code)
        case let .serverError(statusCode, _, _):
            return .httpStatus(code: statusCode)
        case .unauthorized:
            return .unauthorized(statusCode: nil)
        case .transport,
             .retryExhausted,
             .invalidResponse,
             .business,
             .emptyData,
             .unacceptableContentType,
             .decoding,
             .invalidRequest,
             .circuitOpen:
            return .transport
        }
    }

    static func resolve(statusCode: Int) -> BackgroundTransferFailureReason {
        switch statusCode {
        case 401, 403:
            return .unauthorized(statusCode: statusCode)
        default:
            return .httpStatus(code: statusCode)
        }
    }

    var summary: String {
        switch self {
        case .cancelled:
            return "下载已取消"
        case .offline:
            return "当前网络不可用"
        case .networkLost:
            return "网络连接已中断"
        case .timeout:
            return "下载超时"
        case .dnsFailure:
            return "域名解析失败"
        case .cannotConnect:
            return "无法连接服务器"
        case .tlsFailure:
            return "安全连接失败"
        case .serverTrustFailure:
            return "服务器证书校验失败"
        case let .unauthorized(statusCode):
            if let statusCode {
                return "访问未授权 · HTTP \(statusCode)"
            }
            return "访问未授权"
        case let .httpStatus(code):
            return "服务器返回 HTTP \(code)"
        case .fileSystem:
            return "文件写入失败"
        case .networkAccessRestricted:
            return "当前网络环境不允许下载"
        case .transport:
            return "下载链路异常"
        case .unknown:
            return "下载失败"
        }
    }

    func recoveryDescription(resumeDataAvailable: Bool) -> String {
        if resumeDataAvailable {
            return "可继续下载"
        }

        switch self {
        case .cancelled:
            return "可重新发起下载"
        case .offline, .networkLost, .networkAccessRestricted:
            return "网络恢复后可重试"
        case .timeout, .dnsFailure, .cannotConnect, .transport, .unknown:
            return "可重试下载"
        case .tlsFailure, .serverTrustFailure:
            return "检查网络或证书后重试"
        case .unauthorized:
            return "更新登录状态后重试"
        case let .httpStatus(code):
            switch code {
            case 404, 410:
                return "确认资源有效后重试"
            case 408, 409, 423, 425, 429, 500, 502, 503, 504:
                return "服务恢复后可重试"
            default:
                return "可重新发起下载"
            }
        case .fileSystem:
            return "检查存储空间或文件权限后重试"
        }
    }

    func actionTitle(resumeDataAvailable: Bool) -> String {
        resumeDataAvailable ? "继续" : "重试"
    }

    var metricsValue: String {
        switch self {
        case .cancelled:
            return "cancelled"
        case .offline:
            return "offline"
        case .networkLost:
            return "network_lost"
        case .timeout:
            return "timeout"
        case .dnsFailure:
            return "dns_failure"
        case .cannotConnect:
            return "cannot_connect"
        case .tlsFailure:
            return "tls_failure"
        case .serverTrustFailure:
            return "server_trust_failure"
        case .unauthorized:
            return "unauthorized"
        case .httpStatus:
            return "http_status"
        case .fileSystem:
            return "file_system"
        case .networkAccessRestricted:
            return "network_access_restricted"
        case .transport:
            return "transport"
        case .unknown:
            return "unknown"
        }
    }

    var statusCode: Int? {
        switch self {
        case let .unauthorized(statusCode):
            return statusCode
        case let .httpStatus(code):
            return code
        case .cancelled,
             .offline,
             .networkLost,
             .timeout,
             .dnsFailure,
             .cannotConnect,
             .tlsFailure,
             .serverTrustFailure,
             .fileSystem,
             .networkAccessRestricted,
             .transport,
             .unknown:
            return nil
        }
    }
}

public extension BackgroundTransferState {
    var isTerminal: Bool {
        switch self {
        case .failed, .completed:
            return true
        case .pending, .running, .paused:
            return false
        }
    }

    var recoveryActionTitle: String? {
        switch self {
        case let .failed(reason, _, resumeDataAvailable):
            return reason.actionTitle(
                resumeDataAvailable: resumeDataAvailable
            )
        case let .paused(resumeDataAvailable):
            return resumeDataAvailable ? "继续" : "重试"
        case .pending, .running, .completed:
            return nil
        }
    }
}
