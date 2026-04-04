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

// MARK: - Protocol

/// Abstraction over the route cache so tests can inject time-controlled mocks.
protocol CacheStore {
    func save(_ cache: SharedRouteCache)
    func load() -> SharedRouteCache?
    func clear()
    func isValid(cache: SharedRouteCache, currentLat: Double, currentLon: Double, ttl: TimeInterval) -> Bool
}

// MARK: - Concrete Implementation

final class SharedRouteCacheService: CacheStore {

    // MARK: - Configuration

    static let defaultTTL: TimeInterval = 30 * 60   // 30 minutes
    static let locationThresholdMiles: Double = 1.0  // refetch if user moves >1 mile

    /// Production shared instance.
    static let shared = SharedRouteCacheService()

    private let fileManager: FileManager
    private let storageURL: URL
    private let now: () -> Date  // injectable clock for TTL testing

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.now = now
        let base = directory ?? {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
            return appSupport
        }()
        self.storageURL = base.appendingPathComponent("shared_route_cache.json")
    }

    // MARK: - Save

    func save(_ cache: SharedRouteCache) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.cache.error("Failed to save shared route cache: \(error)")
        }
    }

    // MARK: - Load

    func load() -> SharedRouteCache? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SharedRouteCache.self, from: data)
        } catch {
            AppLogger.cache.error("Failed to load shared route cache: \(error)")
            return nil
        }
    }

    // MARK: - Invalidation

    func clear() {
        try? fileManager.removeItem(at: storageURL)
    }

    // MARK: - Validity

    /// Returns `true` if the cache is within TTL and the user hasn't moved
    /// more than `locationThresholdMiles` from the cached location.
    func isValid(
        cache: SharedRouteCache,
        currentLat: Double,
        currentLon: Double,
        ttl: TimeInterval = SharedRouteCacheService.defaultTTL
    ) -> Bool {
        let age = now().timeIntervalSince(cache.cachedAt)
        guard age < ttl else { return false }

        let distance = Self.distanceMiles(
            lat1: cache.userLat, lon1: cache.userLon,
            lat2: currentLat, lon2: currentLon
        )
        return distance < SharedRouteCacheService.locationThresholdMiles
    }

    // MARK: - Haversine Distance (miles)

    static func distanceMiles(
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

    // MARK: - Static Convenience (delegates to shared instance)

    static func save(_ cache: SharedRouteCache) { shared.save(cache) }
    static func load() -> SharedRouteCache? { shared.load() }
    static func clear() { shared.clear() }
    static func isValid(
        cache: SharedRouteCache,
        currentLat: Double,
        currentLon: Double,
        ttl: TimeInterval = SharedRouteCacheService.defaultTTL
    ) -> Bool {
        shared.isValid(cache: cache, currentLat: currentLat, currentLon: currentLon, ttl: ttl)
    }
}
