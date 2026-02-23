//
//  RouteStorageService.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 2/23/26.
//

import Foundation

enum RouteStorageService {

    private static var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved_routes.json")
    }

    static func loadRoutes() -> [String: [Route]]? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode([String: [Route]].self, from: data)
        } catch {
            print("Failed to load routes: \(error)")
            return nil
        }
    }

    static func saveRoutes(_ routes: [String: [Route]]) {
        do {
            let data = try JSONEncoder().encode(routes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save routes: \(error)")
        }
    }
}
