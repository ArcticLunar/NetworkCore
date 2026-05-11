// Copyright (c) 2026 ArcticLunar
// All rights reserved.

import Foundation

public final class BackgroundTransferSystemCoordinator: @unchecked Sendable {
    public static let shared = BackgroundTransferSystemCoordinator()

    private let lock = NSLock()
    private var pendingCompletionHandlers: [String: () -> Void] = [:]
    private var handlerRegistrations: [String: (@escaping () -> Void) -> Void] = [:]

    private init() {}

    public func handleEvents(
        forBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let registration = lock.withLock {
            handlerRegistrations[identifier]
        }

        if let registration {
            registration(completionHandler)
            return
        }

        lock.withLock {
            pendingCompletionHandlers[identifier] = completionHandler
        }
    }

    func register(
        sessionIdentifier: String,
        completionHandlerRegistrar: @escaping (@escaping () -> Void) -> Void
    ) {
        let pendingHandler = lock.withLock {
            handlerRegistrations[sessionIdentifier] = completionHandlerRegistrar
            return pendingCompletionHandlers.removeValue(forKey: sessionIdentifier)
        }

        if let pendingHandler {
            completionHandlerRegistrar(pendingHandler)
        }
    }

    func unregister(sessionIdentifier: String) {
        lock.withLock {
            _ = handlerRegistrations.removeValue(forKey: sessionIdentifier)
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
