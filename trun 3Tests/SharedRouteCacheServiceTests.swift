//
//  SharedRouteCacheServiceTests.swift
//  trun 3Tests
//
//  Tests for SharedRouteCacheService — caches shared route metadata locally
//  to reduce Firestore read costs. Tests cover save/load round-trips,
//  TTL-based expiration, location-based invalidation (user moved >1 mile),
//  and the Haversine distance calculation used for cache validity checks.
//

import XCTest
@testable import trun_3

final class SharedRouteCacheServiceTests: XCTestCase {

    private var tempDir: URL!
    private var fixedDate: Date!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fixedDate = Date()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        fixedDate = nil
        super.tearDown()
    }

    /// Creates a cache service with a controllable clock for TTL testing.
    private func makeSUT(now: @escaping () -> Date = { Date() }) -> SharedRouteCacheService {
        SharedRouteCacheService(fileManager: .default, directory: tempDir, now: now)
    }

    private func makeCache(
        routes: [SharedRoute] = [],
        cachedAt: Date? = nil,
        lat: Double = 37.7749,
        lon: Double = -122.4194,
        radius: Double = 10.0
    ) -> SharedRouteCache {
        SharedRouteCache(
            routes: routes,
            cachedAt: cachedAt ?? fixedDate,
            userLat: lat,
            userLon: lon,
            radiusMiles: radius
        )
    }

    private func makeSampleRoute(id: String = "route-1") -> SharedRoute {
        SharedRoute(
            id: id,
            name: "Test Route",
            distanceMiles: 3.5,
            centerLat: 37.7749,
            centerLon: -122.4194,
            runCount: 10,
            createdAt: Date()
        )
    }

    // MARK: - Save & Load

    /// Saving a cache and immediately loading it should return the same routes.
    /// This verifies the JSON encoding/decoding round-trip works correctly,
    /// including the ISO 8601 date encoding strategy.
    func test_saveAndLoad_roundTrip() throws {
        let sut = makeSUT()
        let route = makeSampleRoute()
        let cache = makeCache(routes: [route])

        sut.save(cache)
        let loaded = try XCTUnwrap(sut.load())

        XCTAssertEqual(loaded.routes.count, 1, "Should round-trip exactly one route")
        XCTAssertEqual(loaded.routes[0].id, "route-1")
        XCTAssertEqual(loaded.routes[0].name, "Test Route")
        XCTAssertEqual(loaded.userLat, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(loaded.userLon, -122.4194, accuracy: 0.0001)
    }

    /// Loading from an empty (no file exists) cache should return nil,
    /// not crash or return a default value.
    func test_load_returnsNil_whenNoFileExists() {
        let sut = makeSUT()
        XCTAssertNil(sut.load(), "No cache file should mean nil, not empty cache")
    }

    /// Saving a second cache should overwrite the first completely.
    func test_save_overwritesPreviousCache() throws {
        let sut = makeSUT()
        sut.save(makeCache(routes: [makeSampleRoute(id: "old")]))
        sut.save(makeCache(routes: [makeSampleRoute(id: "new")]))

        let loaded = try XCTUnwrap(sut.load())
        XCTAssertEqual(loaded.routes.count, 1)
        XCTAssertEqual(loaded.routes[0].id, "new", "Second save should overwrite the first")
    }

    // MARK: - Clear

    /// After clearing, load should return nil and the cache file should be gone.
    func test_clear_removesCache() {
        let sut = makeSUT()
        sut.save(makeCache(routes: [makeSampleRoute()]))
        sut.clear()

        XCTAssertNil(sut.load(), "Cache should be nil after clear")
    }

    /// Clearing when no cache exists should not crash (idempotent operation).
    func test_clear_isIdempotent() {
        let sut = makeSUT()
        sut.clear() // no file to remove
        XCTAssertNil(sut.load(), "Clear on empty cache should be a no-op")
    }

    // MARK: - isValid (TTL)

    /// A cache created 1 minute ago should be valid (well within the 30-minute TTL).
    func test_isValid_returnsTrue_withinTTL() {
        let oneMinuteAgo = fixedDate.addingTimeInterval(-60)
        let sut = makeSUT(now: { self.fixedDate })
        let cache = makeCache(cachedAt: oneMinuteAgo)

        XCTAssertTrue(
            sut.isValid(cache: cache, currentLat: 37.7749, currentLon: -122.4194),
            "Cache from 1 minute ago should still be valid"
        )
    }

    /// A cache older than the TTL (default 30 minutes) should be invalid,
    /// forcing a fresh Firestore fetch.
    func test_isValid_returnsFalse_afterTTLExpired() {
        let thirtyOneMinutesAgo = fixedDate.addingTimeInterval(-31 * 60)
        let sut = makeSUT(now: { self.fixedDate })
        let cache = makeCache(cachedAt: thirtyOneMinutesAgo)

        XCTAssertFalse(
            sut.isValid(cache: cache, currentLat: 37.7749, currentLon: -122.4194),
            "Cache older than 30 minutes should be expired"
        )
    }

    /// A custom TTL can be passed to isValid. A 5-second TTL with a 10-second-old
    /// cache should be invalid.
    func test_isValid_respectsCustomTTL() {
        let tenSecondsAgo = fixedDate.addingTimeInterval(-10)
        let sut = makeSUT(now: { self.fixedDate })
        let cache = makeCache(cachedAt: tenSecondsAgo)

        XCTAssertFalse(
            sut.isValid(cache: cache, currentLat: 37.7749, currentLon: -122.4194, ttl: 5),
            "10-second-old cache should be invalid with a 5-second TTL"
        )
    }

    // MARK: - isValid (location drift)

    /// If the user has moved more than 1 mile from where the cache was created,
    /// the cached results are stale (different area) and should be refetched.
    func test_isValid_returnsFalse_whenUserMovedOverOneMile() {
        let sut = makeSUT(now: { self.fixedDate })
        // Cache was created at (37.7749, -122.4194) — San Francisco
        let cache = makeCache(cachedAt: fixedDate)

        // Move user ~2 miles north (0.029 degrees ≈ 2 miles)
        let movedLat = 37.7749 + 0.029
        XCTAssertFalse(
            sut.isValid(cache: cache, currentLat: movedLat, currentLon: -122.4194),
            "Cache should be invalid when user moved >1 mile from cached location"
        )
    }

    /// Small movements (< 1 mile) should not invalidate the cache.
    func test_isValid_returnsTrue_whenUserMovedLessThanOneMile() {
        let sut = makeSUT(now: { self.fixedDate })
        let cache = makeCache(cachedAt: fixedDate)

        // Move user ~0.3 miles north (0.0044 degrees ≈ 0.3 miles)
        let movedLat = 37.7749 + 0.0044
        XCTAssertTrue(
            sut.isValid(cache: cache, currentLat: movedLat, currentLon: -122.4194),
            "Cache should remain valid for small movements under 1 mile"
        )
    }

    // MARK: - Haversine distanceMiles

    /// Two identical points should have exactly 0 distance.
    func test_distanceMiles_samePoint_isZero() {
        let d = SharedRouteCacheService.distanceMiles(
            lat1: 37.7749, lon1: -122.4194,
            lat2: 37.7749, lon2: -122.4194
        )
        XCTAssertEqual(d, 0.0, accuracy: 0.001, "Same point should be 0 miles apart")
    }

    /// San Francisco (37.7749, -122.4194) to Los Angeles (34.0522, -118.2437)
    /// is approximately 347 miles by great-circle distance.
    func test_distanceMiles_sfToLA_approximately347Miles() {
        let d = SharedRouteCacheService.distanceMiles(
            lat1: 37.7749, lon1: -122.4194,
            lat2: 34.0522, lon2: -118.2437
        )
        XCTAssertEqual(d, 347, accuracy: 10, "SF to LA should be ~347 miles by Haversine")
    }

    /// The Haversine formula should be symmetric — distance(A, B) == distance(B, A).
    func test_distanceMiles_isSymmetric() {
        let d1 = SharedRouteCacheService.distanceMiles(
            lat1: 37.7749, lon1: -122.4194,
            lat2: 40.7128, lon2: -74.0060
        )
        let d2 = SharedRouteCacheService.distanceMiles(
            lat1: 40.7128, lon1: -74.0060,
            lat2: 37.7749, lon2: -122.4194
        )
        XCTAssertEqual(d1, d2, accuracy: 0.001, "Haversine distance should be symmetric")
    }
}
