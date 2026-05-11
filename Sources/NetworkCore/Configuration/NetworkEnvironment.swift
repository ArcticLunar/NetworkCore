// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public struct NetworkEnvironment: Equatable {
    public let name: String
    public let baseURL: URL

    public init(name: String, baseURL: URL) {
        self.name = name
        self.baseURL = baseURL
    }
}
