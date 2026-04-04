//
//  RunSessionManagerTests.swift
//  trun 3Tests
//

import XCTest
@testable import trun_3

// MARK: - Mock

final class MockLiveActivityService: LiveActivityManaging {
    private(set) var startCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var lastUpdateIsPaused: Bool?
    var shouldThrow = false

    func start(activityType: String, isRouteRun: Bool, pace: String) throws {
        if shouldThrow { throw MockError.forced }
        startCount += 1
    }

    func update(distanceMiles: Double, pace: String, elapsedSeconds: Double, isPaused: Bool) async {
        updateCount += 1
        lastUpdateIsPaused = isPaused
    }

    func end(distanceMiles: Double, pace: String, elapsedSeconds: Double) {
        endCount += 1
    }

    enum MockError: Error { case forced }
}

// MARK: - Tests

final class RunSessionManagerTests: XCTestCase {

    private var sut: RunSessionManager!
    private var mock: MockLiveActivityService!

    override func setUp() {
        super.setUp()
        mock = MockLiveActivityService()
        sut = RunSessionManager(liveActivityService: mock)
    }

    override func tearDown() {
        sut = nil
        mock = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        XCTAssertEqual(sut.runState, .idle)
    }

    func test_isPaused_false_initially() {
        XCTAssertFalse(sut.isPaused)
    }

    func test_isRunDone_false_initially() {
        XCTAssertFalse(sut.isRunDone)
    }

    // MARK: - RunState transitions

    func test_settingIsPausedTrue_setsState_paused() {
        sut.isPaused = true
        XCTAssertEqual(sut.runState, .paused)
    }

    func test_settingIsPausedFalse_afterPause_setsState_running() {
        sut.isPaused = true
        sut.isPaused = false
        XCTAssertEqual(sut.runState, .running)
    }

    func test_settingIsTimerPausedTrue_setsState_paused() {
        sut.isTimerPaused = true
        XCTAssertEqual(sut.runState, .paused)
        XCTAssertTrue(sut.isPaused)
    }

    func test_settingIsRunDoneTrue_setsState_completed() {
        sut.isRunDone = true
        XCTAssertEqual(sut.runState, .completed)
    }

    func test_settingIsRunDoneFalse_setsState_idle() {
        sut.isRunDone = true
        sut.isRunDone = false
        XCTAssertEqual(sut.runState, .idle)
    }

    func test_directAssignment_running_computedVarsReflect() {
        sut.runState = .running
        XCTAssertFalse(sut.isPaused)
        XCTAssertFalse(sut.isRunDone)
    }

    func test_directAssignment_completed_isRunDoneTrue() {
        sut.runState = .completed
        XCTAssertTrue(sut.isRunDone)
    }

    // MARK: - LiveActivity forwarding

    func test_updateLiveActivity_callsServiceUpdate() async {
        sut.updateLiveActivity(distanceMiles: 1.5, pace: "8:30", elapsedSeconds: 765, isPaused: false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(mock.updateCount, 1)
        XCTAssertEqual(mock.lastUpdateIsPaused, false)
    }

    func test_updateLiveActivity_propagatesPausedFlag() async {
        sut.updateLiveActivity(distanceMiles: 0.5, pace: "9:00", elapsedSeconds: 300, isPaused: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(mock.lastUpdateIsPaused, true)
    }

    func test_endLiveActivity_callsServiceEnd() {
        sut.endLiveActivity()
        XCTAssertEqual(mock.endCount, 1)
    }

    // MARK: - RunState equality

    func test_runState_equality() {
        XCTAssertEqual(RunState.idle, RunState.idle)
        XCTAssertNotEqual(RunState.idle, RunState.running)
        XCTAssertNotEqual(RunState.paused, RunState.completed)
    }
}
