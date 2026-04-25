import Foundation

public enum NetworkSecurityPolicy: Equatable {
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

    case configuredSystemDefault(SystemDefaultConfiguration)
    case configuredPinnedCertificates(CertificatePinningConfiguration)
    case configuredPublicKeyPinning(PublicKeyPinningConfiguration)

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
