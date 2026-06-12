// Copyright (c) 2026 ArcticLunar
// All rights reserved.

// 封装 Alamofire server trust 配置，避免业务层直接依赖评估器细节。

import Foundation

/// 网络安全策略，用于创建 `ServerTrustManager`。
public enum NetworkSecurityPolicy: Equatable {
    /// 使用系统默认信任链校验的配置。
    public struct SystemDefaultConfiguration: Equatable {
        public let hosts: [String]
        public let allHostsMustBeEvaluated: Bool
        public let validateHost: Bool

        public init(
            hosts: [String] = [],
            allHostsMustBeEvaluated: Bool = false,
            validateHost: Bool = true
        ) {
            self.hosts = NetworkSecurityPolicy.normalizedHosts(hosts)
            self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
            self.validateHost = validateHost
        }
    }

    /// 使用证书固定的配置。
    public struct CertificatePinningConfiguration: Equatable {
        public let hosts: [String]
        public let certificateData: [Data]
        public let allHostsMustBeEvaluated: Bool
        public let acceptSelfSignedCertificates: Bool
        public let performDefaultValidation: Bool
        public let validateHost: Bool

        public init(
            hosts: [String],
            certificateData: [Data],
            allHostsMustBeEvaluated: Bool = true,
            acceptSelfSignedCertificates: Bool = false,
            performDefaultValidation: Bool = true,
            validateHost: Bool = true
        ) {
            self.hosts = NetworkSecurityPolicy.normalizedHosts(hosts)
            self.certificateData = certificateData
            self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
            self.acceptSelfSignedCertificates = acceptSelfSignedCertificates
            self.performDefaultValidation = performDefaultValidation
            self.validateHost = validateHost
        }
    }

    /// 使用公钥固定的配置。
    public struct PublicKeyPinningConfiguration: Equatable {
        public let hosts: [String]
        public let certificateData: [Data]
        public let allHostsMustBeEvaluated: Bool
        public let performDefaultValidation: Bool
        public let validateHost: Bool

        public init(
            hosts: [String],
            certificateData: [Data],
            allHostsMustBeEvaluated: Bool = true,
            performDefaultValidation: Bool = true,
            validateHost: Bool = true
        ) {
            self.hosts = NetworkSecurityPolicy.normalizedHosts(hosts)
            self.certificateData = certificateData
            self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
            self.performDefaultValidation = performDefaultValidation
            self.validateHost = validateHost
        }
    }

    /// 系统默认 trust 校验。
    case configuredSystemDefault(SystemDefaultConfiguration)
    /// 证书固定校验。
    case configuredPinnedCertificates(CertificatePinningConfiguration)
    /// 公钥固定校验。
    case configuredPublicKeyPinning(PublicKeyPinningConfiguration)

    /// 创建系统默认 trust 校验策略。
    public static func systemDefault(
        hosts: [String] = [],
        allHostsMustBeEvaluated: Bool = false,
        validateHost: Bool = true
    ) -> Self {
        .configuredSystemDefault(
            SystemDefaultConfiguration(
                hosts: hosts,
                allHostsMustBeEvaluated: allHostsMustBeEvaluated,
                validateHost: validateHost
            )
        )
    }

    /// 创建证书固定策略。
    public static func pinnedCertificates(
        hosts: [String],
        certificateData: [Data],
        allHostsMustBeEvaluated: Bool = true,
        acceptSelfSignedCertificates: Bool = false,
        performDefaultValidation: Bool = true,
        validateHost: Bool = true
    ) -> Self {
        .configuredPinnedCertificates(
            CertificatePinningConfiguration(
                hosts: hosts,
                certificateData: certificateData,
                allHostsMustBeEvaluated: allHostsMustBeEvaluated,
                acceptSelfSignedCertificates: acceptSelfSignedCertificates,
                performDefaultValidation: performDefaultValidation,
                validateHost: validateHost
            )
        )
    }

    /// 创建公钥固定策略。
    public static func publicKeyPinning(
        hosts: [String],
        certificateData: [Data],
        allHostsMustBeEvaluated: Bool = true,
        performDefaultValidation: Bool = true,
        validateHost: Bool = true
    ) -> Self {
        .configuredPublicKeyPinning(
            PublicKeyPinningConfiguration(
                hosts: hosts,
                certificateData: certificateData,
                allHostsMustBeEvaluated: allHostsMustBeEvaluated,
                performDefaultValidation: performDefaultValidation,
                validateHost: validateHost
            )
        )
    }

    fileprivate static func normalizedHosts(_ hosts: [String]) -> [String] {
        Array(Set(hosts.map { $0.lowercased() })).sorted()
    }
}
