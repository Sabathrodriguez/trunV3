//
//  RunPersistenceServiceTests.swift
//  trun 3Tests
//

import XCTest
import CoreLocation
@testable import trun_3

final class RunPersistenceServiceTests: XCTestCase {

    private var tempDir: URL!
    private var sut: RunPersistenceService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = RunPersistenceService(fileManager: .default, directory: tempDir)
    }

    override func tearDownWithError() throws {
        sut = nil
        try FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - hasActiveRun

    func test_hasActiveRun_returnsFalse_whenEmpty() {
        XCTAssertFalse(sut.hasActiveRun())
    }

    func test_hasActiveRun_returnsTrue_afterSave() {
        sut.save(makeSnapshot())
        XCTAssertTrue(sut.hasActiveRun())
    }

    // MARK: - load

    func test_load_returnsNil_whenEmpty() {
        XCTAssertNil(sut.load())
    }

    func test_saveAndLoad_roundTrip() throws {
        let snap = makeSnapshot(timer: 123.4, distance: 500.0)
        sut.save(snap)
        let loaded = try XCTUnwrap(sut.load())
        XCTAssertEqual(loaded.currentTimer, 123.4, accuracy: 0.001)
        XCTAssertEqual(loaded.distance, 500.0, accuracy: 0.001)
    }

    func test_save_overwritesPreviousSnapshot() throws {
        sut.save(makeSnapshot(timer: 10.0))
        sut.save(makeSnapshot(timer: 99.0))
        let loaded = try XCTUnwrap(sut.load())
        XCTAssertEqual(loaded.currentTimer, 99.0, accuracy: 0.001)
    }

    func test_saveAndLoad_preservesPausedState() throws {
        let snap = makeSnapshot(isPaused: true, pauseStartDate: Date().timeIntervalSince1970)
        sut.save(snap)
        let loaded = try XCTUnwrap(sut.load())
        XCTAssertTrue(loaded.isPaused)
        XCTAssertNotNil(loaded.pauseStartDate)
    }

    func test_saveAndLoad_preservesLocations() throws {
        let loc = SerializableLocation(from: CLLocation(latitude: 37.7749, longitude: -122.4194))
        let snap = makeSnapshot(locations: [loc])
        sut.save(snap)
        let loaded = try XCTUnwrap(sut.load())
        XCTAssertEqual(loaded.locations.count, 1)
        XCTAssertEqual(loaded.locations[0].latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(loaded.locations[0].longitude, -122.4194, accuracy: 0.0001)
    }

    // MARK: - clear

    func test_clear_removesFile() {
        sut.save(makeSnapshot())
        sut.clear()
        XCTAssertFalse(sut.hasActiveRun())
        XCTAssertNil(sut.load())
    }

    func test_clear_isIdempotent() {
        sut.clear()
        XCTAssertFalse(sut.hasActiveRun())
    }

    // MARK: - Helpers

    private func makeSnapshot(
        timer: Double = 0.0,
        distance: Double = 0.0,
        isPaused: Bool = false,
        pauseStartDate: Double? = nil,
        locations: [SerializableLocation] = []
    ) -> RunSnapshot {
        RunSnapshot(
            runStartDate: Date().timeIntervalSince1970,
            currentTimer: timer,
            pausedDuration: 0.0,
            isPaused: isPaused,
            isTimerPaused: isPaused,
            pauseStartDate: pauseStartDate,
            distance: distance,
            elevationGain: 0.0,
            locations: locations,
            activityTypeRawValue: 37,
            savedAt: Date().timeIntervalSince1970
        )
    }
}
