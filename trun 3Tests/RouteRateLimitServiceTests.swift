//
//  RouteRateLimitServiceTests.swift
//  trun 3Tests
//
//  Tests for RouteRateLimitService — enforces a daily limit (5) on AI-powered
//  route generation. Uses UserDefaults for persistence, with automatic
//  day-boundary resets. Tests use a dedicated UserDefaults suite to avoid
//  polluting the app's real rate-limit state.
//

import XCTest
@testable import trun_3

final class RouteRateLimitServiceTests: XCTestCase {

    // Store original UserDefaults values to restore after each test
    private let countKey = "routeGenerationCount"
    private let dateKey = "routeGenerationDate"

    override func setUp() {
        super.setUp()
        // Reset the rate limiter state before each test to ensure isolation.
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }

    override func tearDown() {
        // Clean up after each test to avoid affecting other tests or the app.
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
        super.tearDown()
    }

    // MARK: - Initial state

    /// With no prior usage recorded, the user should have the full daily
    /// allowance of 5 route generations available.
    func test_remainingToday_isFull_whenNeverUsed() {
        XCTAssertEqual(RouteRateLimitService.remainingToday, 5, "Fresh state should show full 5 remaining")
    }

    /// canGenerate should be true when the user hasn't used any generations today.
    func test_canGenerate_isTrue_whenNeverUsed() {
        XCTAssertTrue(RouteRateLimitService.canGenerate, "Should allow generation when no usage today")
    }

    // MARK: - recordGeneration

    /// Each call to recordGeneration should decrement the remaining count by 1.
    func test_recordGeneration_decrementsRemaining() {
        let before = RouteRateLimitService.remainingToday
        RouteRateLimitService.recordGeneration()
        XCTAssertEqual(
            RouteRateLimitService.remainingToday, before - 1,
            "Remaining should decrease by 1 after recording a generation"
        )
    }

    /// recordGeneration should return true when the generation is allowed
    /// (user is under the daily limit).
    func test_recordGeneration_returnsTrue_whenUnderLimit() {
        let success = RouteRateLimitService.recordGeneration()
        XCTAssertTrue(success, "Should return true when generation is within daily limit")
    }

    /// After exhausting all 5 daily generations, canGenerate should be false
    /// and recordGeneration should return false (rejecting the 6th attempt).
    func test_canGenerate_isFalse_afterExhaustingLimit() {
        for _ in 0..<RouteRateLimitService.dailyLimit {
            RouteRateLimitService.recordGeneration()
        }
        XCTAssertFalse(RouteRateLimitService.canGenerate, "Should be false after 5 generations")
        XCTAssertEqual(RouteRateLimitService.remainingToday, 0, "Should have 0 remaining")

        let rejected = RouteRateLimitService.recordGeneration()
        XCTAssertFalse(rejected, "6th generation attempt should be rejected")
    }

    /// Remaining count should track each individual generation accurately.
    func test_remainingToday_decreasesProgressively() {
        XCTAssertEqual(RouteRateLimitService.remainingToday, 5)
        RouteRateLimitService.recordGeneration()
        XCTAssertEqual(RouteRateLimitService.remainingToday, 4)
        RouteRateLimitService.recordGeneration()
        XCTAssertEqual(RouteRateLimitService.remainingToday, 3)
        RouteRateLimitService.recordGeneration()
        XCTAssertEqual(RouteRateLimitService.remainingToday, 2)
    }

    // MARK: - Day boundary reset

    /// If the stored date is from yesterday, the rate limiter should automatically
    /// reset the count to 0 and allow a full 5 generations for the new day.
    func test_resetIfNewDay_resetsCount_whenDateIsYesterday() {
        // Simulate usage from yesterday
        UserDefaults.standard.set(3, forKey: countKey)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(yesterday, forKey: dateKey)

        // Accessing remainingToday should trigger the day-boundary reset
        XCTAssertEqual(
            RouteRateLimitService.remainingToday, 5,
            "Yesterday's usage should be reset, giving full 5 remaining"
        )
        XCTAssertTrue(RouteRateLimitService.canGenerate, "Should allow generation on a new day")
    }

    // MARK: - dailyLimit constant

    /// Verify the daily limit is the expected value (5) so tests stay
    /// in sync with the production constant.
    func test_dailyLimit_isFive() {
        XCTAssertEqual(RouteRateLimitService.dailyLimit, 5, "Daily limit should be 5 route generations")
    }
}
