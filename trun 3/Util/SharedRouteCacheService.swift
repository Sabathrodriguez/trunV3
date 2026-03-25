//
//  SharedRouteCacheService.swift
//  trun 3
//
//  Caches shared route metadata locally to reduce Firestore read costs.
//

import Foundation

struct SharedRouteCache: Codable {
    let routes: [SharedRoute]
    let cachedAt: Date
    let userLat: Double
    let userLon: Double
    let radiusMiles: Double
}

enum SharedRouteCacheService {

    // MARK: - Configuration

    static let defaultTTL: TimeInterval = 30 * 60   // 30 minutes
    static let locationThresholdMiles: Double = 1.0  // refetch if user moves >1 mile

    // MARK: - Storage

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("shared_route_cache.json")
    }

    // MARK: - Save

    static func save(_ cache: SharedRouteCache) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SharedRouteCache] Failed to save: \(error)")
        }
    }

    // MARK: - Load

    static func load() -> SharedRouteCache? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SharedRouteCache.self, from: data)
        } catch {
            print("[SharedRouteCache] Failed to load: \(error)")
            return nil
        }
    }

    // MARK: - Invalidation

    static func clear() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Validity

    /// Returns `true` if the cache is within TTL and the user hasn't moved
    /// more than `locationThresholdMiles` from the cached location.
    static func isValid(
        cache: SharedRouteCache,
        currentLat: Double,
        currentLon: Double,
        ttl: TimeInterval = defaultTTL
    ) -> Bool {
        let age = Date().timeIntervalSince(cache.cachedAt)
        guard age < ttl else { return false }

        let distance = distanceMiles(
            lat1: cache.userLat, lon1: cache.userLon,
            lat2: currentLat, lon2: currentLon
        )
        guard distance < locationThresholdMiles else { return false }

        return true
    }

    // MARK: - Haversine Distance (miles)

    private static func distanceMiles(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let R = 3958.8 // Earth radius in miles
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
