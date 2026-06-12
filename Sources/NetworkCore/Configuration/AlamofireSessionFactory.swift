// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 统一创建 Alamofire Session 和 server trust manager。

import Alamofire
import Foundation
#if canImport(Security)
@preconcurrency import Security
#endif

/// 将 NetworkCore 的安全策略转换成 Alamofire 可执行的 Session 配置。
public enum AlamofireSessionFactory {
    /// 创建用于普通请求的 Alamofire Session。
    public static func makeSession(
        timeout: TimeInterval = 15,
        eventMonitors: [any EventMonitor] = [],
        securityPolicy: NetworkSecurityPolicy = .systemDefault()
    ) -> Session {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        return Session(
            configuration: configuration,
            serverTrustManager: makeServerTrustManager(securityPolicy: securityPolicy),
            eventMonitors: eventMonitors
        )
    }

    /// 根据安全策略创建 server trust manager；没有指定 host 时返回 nil 走系统默认行为。
    public static func makeServerTrustManager(
        securityPolicy: NetworkSecurityPolicy
    ) -> ServerTrustManager? {
        switch securityPolicy {
        case let .configuredSystemDefault(configuration):
            return makeServerTrustManager(
                hosts: configuration.hosts,
                allHostsMustBeEvaluated: configuration.allHostsMustBeEvaluated
            ) { _ in
                DefaultTrustEvaluator(validateHost: configuration.validateHost)
            }

        case let .configuredPinnedCertificates(configuration):
            let certificates = secCertificates(from: configuration.certificateData)
            return makeServerTrustManager(
                hosts: configuration.hosts,
                allHostsMustBeEvaluated: configuration.allHostsMustBeEvaluated
            ) { _ in
                PinnedCertificatesTrustEvaluator(
                    certificates: certificates,
                    acceptSelfSignedCertificates: configuration.acceptSelfSignedCertificates,
                    performDefaultValidation: configuration.performDefaultValidation,
                    validateHost: configuration.validateHost
                )
            }

        case let .configuredPublicKeyPinning(configuration):
            let certificates = secCertificates(from: configuration.certificateData)
            let keys = certificates.af.publicKeys
            return makeServerTrustManager(
                hosts: configuration.hosts,
                allHostsMustBeEvaluated: configuration.allHostsMustBeEvaluated
            ) { _ in
                PublicKeysTrustEvaluator(
                    keys: keys,
                    performDefaultValidation: configuration.performDefaultValidation,
                    validateHost: configuration.validateHost
                )
            }
        }
    }

    private static func makeServerTrustManager(
        hosts: [String],
        allHostsMustBeEvaluated: Bool,
        evaluatorBuilder: (String) -> any ServerTrustEvaluating
    ) -> ServerTrustManager? {
        guard hosts.isEmpty == false else {
            return nil
        }

        let evaluators = hosts.reduce(into: [String: any ServerTrustEvaluating]()) { partialResult, host in
            partialResult[host] = evaluatorBuilder(host)
        }

        return ServerTrustManager(
            allHostsMustBeEvaluated: allHostsMustBeEvaluated,
            evaluators: evaluators
        )
    }

    private static func secCertificates(from certificateData: [Data]) -> [SecCertificate] {
        certificateData.compactMap {
            SecCertificateCreateWithData(nil, $0 as CFData)
        }
    }
}
