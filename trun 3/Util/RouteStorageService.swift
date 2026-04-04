//
//  RouteStorageService.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 2/23/26.
//

import Foundation

// MARK: - Protocol

/// Abstraction over local route file storage so tests can inject a mock.
protocol RouteStorage {
    func loadRoutes() -> [String: [Route]]?
    func saveRoutes(_ routes: [String: [Route]])
}

// MARK: - Concrete Implementation

final class RouteStorageService: RouteStorage {

    /// Production shared instance.
    static let shared = RouteStorageService()

    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        let base = directory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = base.appendingPathComponent("saved_routes.json")
    }

    func loadRoutes() -> [String: [Route]]? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode([String: [Route]].self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to load routes: \(error)")
            return nil
        }
    }

    func saveRoutes(_ routes: [String: [Route]]) {
        do {
            let data = try JSONEncoder().encode(routes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to save routes: \(error)")
        }
    }

    // MARK: - Static Convenience (delegates to shared instance)

    static func loadRoutes() -> [String: [Route]]? { shared.loadRoutes() }
    static func saveRoutes(_ routes: [String: [Route]]) { shared.saveRoutes(routes) }
}
