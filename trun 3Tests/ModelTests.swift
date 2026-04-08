//
//  ModelTests.swift
//  trun 3Tests
//
//  Tests for data model structs: Route, Runner, SharedRoute, LeaderboardEntry,
//  RunActivityAttributes, SerializableLocation, and RunSnapshot.
//  Validates construction, Codable conformance, Equatable/Hashable behavior,
//  and protocol conformances that the rest of the app depends on.
//

import XCTest
import CoreLocation
import SwiftUI
@testable import trun_3

// MARK: - Route Tests

final class RouteTests: XCTestCase {

    /// Route should be constructable with all fields and retain values correctly.
    func test_route_initializesCorrectly() {
        let route = Route(
            id: 123.0,
            name: "Morning Loop",
            GPXFileURL: "file:///path/to/route.gpx",
            color: [1.0, 0.0, 0.0, 1.0],
            sharedRouteID: "shared-abc"
        )
        XCTAssertEqual(route.id, 123.0)
        XCTAssertEqual(route.name, "Morning Loop")
        XCTAssertEqual(route.GPXFileURL, "file:///path/to/route.gpx")
        XCTAssertEqual(route.color, [1.0, 0.0, 0.0, 1.0])
        XCTAssertEqual(route.sharedRouteID, "shared-abc")
    }

    /// Route's sharedRouteID is optional — should default to nil
    /// for routes that haven't been published to the shared library.
    func test_route_sharedRouteID_canBeNil() {
        let route = Route(id: 1.0, name: "Local", GPXFileURL: "", color: [])
        XCTAssertNil(route.sharedRouteID)
    }

    /// Route conforms to Codable for JSON persistence in RouteStorageService.
    /// Verify the round-trip preserves all fields including optionals.
    func test_route_codableRoundTrip() throws {
        let original = Route(
            id: 42.5,
            name: "Test",
            GPXFileURL: "/test.gpx",
            color: [0.5, 0.5, 0.5, 1.0],
            sharedRouteID: "abc"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Route.self, from: data)
        XCTAssertEqual(decoded, original, "Route should survive JSON round-trip")
    }

    /// Two routes with the same properties should be equal (Equatable).
    func test_route_equatable() {
        let a = Route(id: 1.0, name: "A", GPXFileURL: "a.gpx", color: [1, 0, 0, 1])
        let b = Route(id: 1.0, name: "A", GPXFileURL: "a.gpx", color: [1, 0, 0, 1])
        XCTAssertEqual(a, b, "Routes with identical properties should be equal")
    }

    /// Routes with different IDs should not be equal.
    func test_route_notEqual_differentID() {
        let a = Route(id: 1.0, name: "A", GPXFileURL: "a.gpx", color: [1, 0, 0, 1])
        let b = Route(id: 2.0, name: "A", GPXFileURL: "a.gpx", color: [1, 0, 0, 1])
        XCTAssertNotEqual(a, b, "Routes with different IDs should not be equal")
    }

    /// Route conforms to Hashable (needed for SwiftUI ForEach and Set usage).
    func test_route_hashable() {
        let route = Route(id: 1.0, name: "A", GPXFileURL: "a.gpx", color: [1, 0, 0, 1])
        var set = Set<Route>()
        set.insert(route)
        XCTAssertTrue(set.contains(route), "Route should be usable in a Set")
    }
}

// MARK: - Runner Tests

final class RunnerTests: XCTestCase {

    /// Runner can be initialized from Firebase RTDB snapshot data.
    /// This simulates the data format that LiveRunService receives from Firebase.
    func test_runner_initFromFirebaseData() {
        let data: [String: Any] = [
            "n": "Alice",
            "la": 37.7749,
            "lo": -122.4194,
            "p": 0.75
        ]
        let runner = Runner(id: "user-123", data: data, routeID: "route-1", runnerIndex: 0)

        XCTAssertEqual(runner.id, "user-123")
        XCTAssertEqual(runner.name, "Alice")
        XCTAssertEqual(runner.location.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(runner.location.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(runner.routeProgress, 0.75, accuracy: 0.001)
        XCTAssertEqual(runner.routeID, "route-1")
    }

    /// When Firebase data is missing the name field ("n"), the runner should
    /// get a default name based on their index in the runners list.
    func test_runner_defaultName_whenMissingFromData() {
        let data: [String: Any] = ["la": 0.0, "lo": 0.0]
        let runner = Runner(id: "user-456", data: data, routeID: "r", runnerIndex: 2)
        XCTAssertEqual(runner.name, "Runner 3", "Should use 1-based index for default name")
    }

    /// When Firebase data is missing lat/lon, they should default to 0.
    func test_runner_defaultCoordinates_whenMissing() {
        let data: [String: Any] = [:]
        let runner = Runner(id: "u", data: data, routeID: "r", runnerIndex: 0)
        XCTAssertEqual(runner.location.latitude, 0.0, accuracy: 0.0001)
        XCTAssertEqual(runner.location.longitude, 0.0, accuracy: 0.0001)
    }

    /// The manual initializer is used for local testing and preview data.
    /// All parameters should be stored correctly.
    func test_runner_manualInit() {
        let runner = Runner(
            id: "local-1",
            name: "Bob",
            location: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            color: .blue,
            routeID: "route-2",
            routeProgress: 0.5,
            pace: "8:30",
            distanceMiles: 2.5
        )
        XCTAssertEqual(runner.name, "Bob")
        XCTAssertEqual(runner.pace, "8:30")
        XCTAssertEqual(runner.distanceMiles, 2.5, accuracy: 0.001)
    }

    /// Runner equality is based on id, location, routeProgress, pace, and distanceMiles.
    /// Two runners with the same values should be equal.
    func test_runner_equatable_sameValues() {
        let loc = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let a = Runner(id: "1", name: "A", location: loc, color: .red, routeID: "r", routeProgress: 0.5, pace: "9:00", distanceMiles: 1.0)
        let b = Runner(id: "1", name: "A", location: loc, color: .red, routeID: "r", routeProgress: 0.5, pace: "9:00", distanceMiles: 1.0)
        XCTAssertEqual(a, b)
    }

    /// Runners with different IDs should not be equal, even if all other fields match.
    func test_runner_notEqual_differentID() {
        let loc = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let a = Runner(id: "1", name: "A", location: loc, color: .red, routeID: "r")
        let b = Runner(id: "2", name: "A", location: loc, color: .red, routeID: "r")
        XCTAssertNotEqual(a, b)
    }

    /// Runner's Hashable conformance uses only the id, so runners with the
    /// same id should hash to the same bucket.
    func test_runner_hashable_usesID() {
        let loc = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let a = Runner(id: "same", name: "A", location: loc, color: .red, routeID: "r")
        let b = Runner(id: "same", name: "B", location: loc, color: .blue, routeID: "r2")
        XCTAssertEqual(a.hashValue, b.hashValue, "Same id should produce same hash")
    }
}

// MARK: - SharedRoute Tests

final class SharedRouteTests: XCTestCase {

    /// SharedRoute should be constructable and retain all fields.
    func test_sharedRoute_initializesCorrectly() {
        let now = Date()
        let route = SharedRoute(
            id: "shared-1",
            name: "Golden Gate Loop",
            distanceMiles: 6.2,
            centerLat: 37.8199,
            centerLon: -122.4783,
            runCount: 42,
            createdAt: now
        )
        XCTAssertEqual(route.id, "shared-1")
        XCTAssertEqual(route.name, "Golden Gate Loop")
        XCTAssertEqual(route.distanceMiles, 6.2, accuracy: 0.001)
        XCTAssertEqual(route.runCount, 42)
    }

    /// SharedRoute must be Codable for caching in SharedRouteCacheService.
    func test_sharedRoute_codableRoundTrip() throws {
        let original = SharedRoute(
            id: "test",
            name: "Test",
            distanceMiles: 3.0,
            centerLat: 37.0,
            centerLon: -122.0,
            runCount: 5,
            createdAt: Date(timeIntervalSince1970: 1700000000) // fixed date for deterministic encoding
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SharedRoute.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.distanceMiles, original.distanceMiles, accuracy: 0.001)
    }
}

// MARK: - LeaderboardEntry Tests

final class LeaderboardEntryTests: XCTestCase {

    /// LeaderboardEntry should be constructable with all fields.
    func test_leaderboardEntry_initializesCorrectly() {
        let entry = LeaderboardEntry(
            id: "entry-1",
            uid: "user-abc",
            rank: 1,
            pace: "7:30",
            time: 1350.0,
            distance: 3.1,
            date: Date(),
            isCurrentUser: true
        )
        XCTAssertEqual(entry.rank, 1)
        XCTAssertEqual(entry.pace, "7:30")
        XCTAssertTrue(entry.isCurrentUser)
    }

    /// The id property is used for Identifiable conformance in SwiftUI lists.
    func test_leaderboardEntry_isIdentifiable() {
        let entry = LeaderboardEntry(
            id: "unique-id",
            uid: "u",
            rank: 1,
            pace: "",
            time: 0,
            distance: 0,
            date: Date(),
            isCurrentUser: false
        )
        XCTAssertEqual(entry.id, "unique-id")
    }
}

// MARK: - RunActivityAttributes Tests

final class RunActivityAttributesTests: XCTestCase {

    /// RunActivityAttributes should store the activity type string and route flag.
    func test_attributes_initializesCorrectly() {
        let attrs = RunActivityAttributes(activityType: "Running", isRouteRun: true)
        XCTAssertEqual(attrs.activityType, "Running")
        XCTAssertTrue(attrs.isRouteRun)
    }

    /// ContentState stores the live-updating data for the Live Activity widget.
    /// Verify all fields are preserved including the virtual timer date.
    func test_contentState_initializesCorrectly() {
        let now = Date()
        let state = RunActivityAttributes.ContentState(
            distanceMiles: 2.5,
            pace: "8:15",
            timerDate: now,
            isPaused: false,
            elapsedSeconds: 1234.5
        )
        XCTAssertEqual(state.distanceMiles, 2.5, accuracy: 0.001)
        XCTAssertEqual(state.pace, "8:15")
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.elapsedSeconds, 1234.5, accuracy: 0.01)
    }

    /// ContentState conforms to Hashable (required by ActivityKit).
    func test_contentState_hashable() {
        let now = Date()
        let a = RunActivityAttributes.ContentState(distanceMiles: 1.0, pace: "9:00", timerDate: now, isPaused: false, elapsedSeconds: 100)
        let b = RunActivityAttributes.ContentState(distanceMiles: 1.0, pace: "9:00", timerDate: now, isPaused: false, elapsedSeconds: 100)
        XCTAssertEqual(a, b, "Identical ContentStates should be equal (Hashable)")
    }

    /// ContentState must be Codable for ActivityKit serialization.
    func test_contentState_codableRoundTrip() throws {
        let original = RunActivityAttributes.ContentState(
            distanceMiles: 5.0,
            pace: "7:45",
            timerDate: Date(timeIntervalSince1970: 1700000000),
            isPaused: true,
            elapsedSeconds: 3600
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RunActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.distanceMiles, original.distanceMiles, accuracy: 0.001)
        XCTAssertEqual(decoded.pace, original.pace)
        XCTAssertEqual(decoded.isPaused, original.isPaused)
    }
}

// MARK: - SerializableLocation Tests

final class SerializableLocationTests: XCTestCase {

    /// SerializableLocation should correctly capture all relevant CLLocation properties
    /// for persistence (used when saving in-progress run snapshots).
    func test_initFromCLLocation() {
        let clLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 15.5,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 10.0,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let serializable = SerializableLocation(from: clLocation)

        XCTAssertEqual(serializable.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(serializable.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(serializable.altitude, 15.5, accuracy: 0.01)
        XCTAssertEqual(serializable.horizontalAccuracy, 5.0, accuracy: 0.01)
        XCTAssertEqual(serializable.timestamp, 1700000000, accuracy: 0.01)
    }

    /// toCLLocation() should reconstruct a CLLocation with the same
    /// coordinate, altitude, accuracy, and timestamp values.
    func test_toCLLocation_roundTrip() {
        let original = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 10.0,
            horizontalAccuracy: 3.0,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let serializable = SerializableLocation(from: original)
        let restored = serializable.toCLLocation()

        XCTAssertEqual(restored.coordinate.latitude, original.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(restored.coordinate.longitude, original.coordinate.longitude, accuracy: 0.0001)
        XCTAssertEqual(restored.altitude, original.altitude, accuracy: 0.01)
        XCTAssertEqual(restored.horizontalAccuracy, original.horizontalAccuracy, accuracy: 0.01)
    }

    /// SerializableLocation must be Codable for JSON persistence in RunSnapshot.
    func test_codableRoundTrip() throws {
        let original = SerializableLocation(from: CLLocation(latitude: 37.0, longitude: -122.0))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SerializableLocation.self, from: data)
        XCTAssertEqual(decoded.latitude, original.latitude, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, original.longitude, accuracy: 0.0001)
    }
}

// MARK: - RunSnapshot Tests

final class RunSnapshotTests: XCTestCase {

    /// RunSnapshot should capture all timing, metric, and location state
    /// needed to fully restore an interrupted run.
    func test_snapshot_initializesCorrectly() {
        let snapshot = RunSnapshot(
            runStartDate: 1700000000,
            currentTimer: 600.0,
            pausedDuration: 30.0,
            isPaused: true,
            isTimerPaused: true,
            pauseStartDate: 1700000590,
            distance: 1609.34,
            elevationGain: 25.0,
            locations: [],
            activityTypeRawValue: 37,
            selectedRouteID: 42.0,
            savedAt: 1700000600
        )
        XCTAssertEqual(snapshot.currentTimer, 600.0, accuracy: 0.01)
        XCTAssertTrue(snapshot.isPaused)
        XCTAssertEqual(snapshot.distance, 1609.34, accuracy: 0.01)
        XCTAssertEqual(snapshot.elevationGain, 25.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.selectedRouteID, 42.0)
    }

    /// RunSnapshot must be Codable for JSON persistence via RunPersistenceService.
    func test_snapshot_codableRoundTrip() throws {
        let loc = SerializableLocation(from: CLLocation(latitude: 37.7749, longitude: -122.4194))
        let original = RunSnapshot(
            runStartDate: 1700000000,
            currentTimer: 300,
            pausedDuration: 0,
            isPaused: false,
            isTimerPaused: false,
            pauseStartDate: nil,
            distance: 500,
            elevationGain: 10,
            locations: [loc],
            activityTypeRawValue: 37,
            selectedRouteID: nil,
            savedAt: 1700000300
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RunSnapshot.self, from: data)

        XCTAssertEqual(decoded.currentTimer, original.currentTimer, accuracy: 0.01)
        XCTAssertEqual(decoded.distance, original.distance, accuracy: 0.01)
        XCTAssertEqual(decoded.locations.count, 1)
        XCTAssertNil(decoded.selectedRouteID)
    }
}
