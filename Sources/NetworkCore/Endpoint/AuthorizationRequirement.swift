// Copyright (c) 2026 ArcticLunar
// All rights reserved.

public enum AuthorizationRequirement: Equatable, Sendable {
    case none
    case bearerToken
    case custom(String)
    case inheritGlobal
}
