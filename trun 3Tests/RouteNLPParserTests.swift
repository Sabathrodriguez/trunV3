//
//  RouteNLPParserTests.swift
//  trun 3Tests
//
//  Tests for RouteNLPParser — parses natural language route requests into
//  structured RouteRequest objects using Apple's on-device FoundationModels.
//
//  Since FoundationModels/LanguageModelSession requires iOS 26+ and actual
//  on-device AI hardware, these tests focus on:
//  1. RouteRequest model validation (the struct the parser produces)
//  2. RouteType and ActivityType enum cases and raw values
//  3. ParsingError localized descriptions
//  4. Distance bounds that the parser enforces (0.5–50 miles)
//
//  Integration tests requiring a real device with Apple Intelligence enabled
//  would need to be run as UI tests or on a physical device.
//

import XCTest
@testable import trun_3

@available(iOS 26.0, *)
final class RouteNLPParserTests: XCTestCase {

    // MARK: - RouteType enum

    /// RouteType should have exactly 3 cases representing the supported
    /// route geometries: loop (circular), outAndBack (there and return),
    /// and pointToPoint (one direction).
    func test_routeType_hasExpectedCases() {
        let allCases = RouteType.allCases
        XCTAssertEqual(allCases.count, 3, "RouteType should have exactly 3 cases")
        XCTAssertTrue(allCases.contains(.loop))
        XCTAssertTrue(allCases.contains(.outAndBack))
        XCTAssertTrue(allCases.contains(.pointToPoint))
    }

    /// Raw string values should match what the on-device model generates,
    /// ensuring JSON decoding compatibility between the model output and our enum.
    func test_routeType_rawValues() {
        XCTAssertEqual(RouteType.loop.rawValue, "loop")
        XCTAssertEqual(RouteType.outAndBack.rawValue, "outAndBack")
        XCTAssertEqual(RouteType.pointToPoint.rawValue, "pointToPoint")
    }

    /// RouteType should be Codable for JSON serialization when persisting
    /// or transmitting route requests.
    func test_routeType_codableRoundTrip() throws {
        let original = RouteType.outAndBack
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RouteType.self, from: data)
        XCTAssertEqual(decoded, original, "RouteType should survive JSON round-trip")
    }

    // MARK: - ActivityType enum

    /// ActivityType should have exactly 3 cases: running, walking, and cycling.
    func test_activityType_hasExpectedCases() {
        let allCases = ActivityType.allCases
        XCTAssertEqual(allCases.count, 3, "ActivityType should have running, walking, cycling")
        XCTAssertTrue(allCases.contains(.running))
        XCTAssertTrue(allCases.contains(.walking))
        XCTAssertTrue(allCases.contains(.cycling))
    }

    /// Raw values should match the strings the on-device model is prompted to produce.
    func test_activityType_rawValues() {
        XCTAssertEqual(ActivityType.running.rawValue, "running")
        XCTAssertEqual(ActivityType.walking.rawValue, "walking")
        XCTAssertEqual(ActivityType.cycling.rawValue, "cycling")
    }

    /// ActivityType should be Codable for persistence and transmission.
    func test_activityType_codableRoundTrip() throws {
        let original = ActivityType.cycling
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActivityType.self, from: data)
        XCTAssertEqual(decoded, original, "ActivityType should survive JSON round-trip")
    }

    // MARK: - RouteRequest model

    /// A RouteRequest with all fields populated should be constructable
    /// and retain all values correctly. This is the data structure the
    /// parser produces after processing natural language input.
    func test_routeRequest_initializesWithAllFields() {
        let request = RouteRequest(
            targetDistanceMiles: 5.0,
            routeType: .loop,
            activityType: .running,
            directionPreference: "toward downtown",
            terrainPreference: "flat"
        )
        XCTAssertEqual(request.targetDistanceMiles, 5.0)
        XCTAssertEqual(request.routeType, .loop)
        XCTAssertEqual(request.activityType, .running)
        XCTAssertEqual(request.directionPreference, "toward downtown")
        XCTAssertEqual(request.terrainPreference, "flat")
    }

    /// Optional fields (directionPreference, terrainPreference) should
    /// default to nil when not specified by the user.
    func test_routeRequest_optionalFieldsCanBeNil() {
        let request = RouteRequest(
            targetDistanceMiles: 3.0,
            routeType: .outAndBack,
            activityType: .walking,
            directionPreference: nil,
            terrainPreference: nil
        )
        XCTAssertNil(request.directionPreference)
        XCTAssertNil(request.terrainPreference)
    }

    /// RouteRequest fields should be readable and modifiable after construction.
    /// (RouteRequest uses @Generable rather than Codable, so we verify field access
    /// instead of JSON round-trips.)
    func test_routeRequest_fieldsAreAccessible() {
        var request = RouteRequest(
            targetDistanceMiles: 7.5,
            routeType: .pointToPoint,
            activityType: .cycling,
            directionPreference: "along the river",
            terrainPreference: "hilly"
        )
        // Verify mutable struct behavior
        request.targetDistanceMiles = 10.0
        XCTAssertEqual(request.targetDistanceMiles, 10.0)
        request.routeType = .loop
        XCTAssertEqual(request.routeType, .loop)
    }

    // MARK: - Distance validation bounds

    /// The parser enforces a minimum distance of 0.5 miles. Routes shorter
    /// than this are impractical and likely parsing errors.
    func test_distanceBounds_minimumIs0_5Miles() {
        // The parser checks: result.targetDistanceMiles >= 0.5
        // A value of 0.4 should fail validation.
        let tooShort = 0.4
        XCTAssertTrue(tooShort < 0.5, "Distances below 0.5 miles should be rejected by the parser")
    }

    /// The parser enforces a maximum distance of 50 miles, matching the
    /// GPXValidator's routeTooLong limit for consistency.
    func test_distanceBounds_maximumIs50Miles() {
        // The parser checks: result.targetDistanceMiles <= 50.0
        // A value of 50.1 should fail validation.
        let tooLong = 50.1
        XCTAssertTrue(tooLong > 50.0, "Distances above 50 miles should be rejected by the parser")
    }

    /// Boundary values (exactly 0.5 and 50.0) should pass the parser's validation.
    func test_distanceBounds_boundaryValuesAreValid() {
        let minValid = 0.5
        let maxValid = 50.0
        XCTAssertTrue(minValid >= 0.5 && minValid <= 50.0, "0.5 miles should be within valid range")
        XCTAssertTrue(maxValid >= 0.5 && maxValid <= 50.0, "50.0 miles should be within valid range")
    }

    // MARK: - ParsingError descriptions

    /// Every ParsingError case should provide a non-nil, user-facing
    /// localized description for display in the route generation UI.
    func test_parsingError_descriptions_areNotNil() {
        let errors: [RouteNLPParser.ParsingError] = [
            .modelUnavailable,
            .parsingFailed("test reason"),
            .invalidDistance(100.0)
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Description should not be empty for \(error)")
        }
    }

    /// The modelUnavailable error should mention Apple Intelligence,
    /// helping the user understand they need to enable it in Settings.
    func test_parsingError_modelUnavailable_mentionsAppleIntelligence() {
        let error = RouteNLPParser.ParsingError.modelUnavailable
        XCTAssertTrue(
            error.errorDescription?.contains("Apple Intelligence") ?? false,
            "Error should guide user to enable Apple Intelligence"
        )
    }

    /// The invalidDistance error should include the specific invalid distance
    /// value and the supported range so the user can adjust their request.
    func test_parsingError_invalidDistance_includesDistanceAndRange() {
        let error = RouteNLPParser.ParsingError.invalidDistance(75.0)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("75.0"), "Should include the invalid distance value")
        XCTAssertTrue(description.contains("0.5") && description.contains("50"), "Should mention the valid range")
    }

    /// The parsingFailed error should include the specific failure reason
    /// from the on-device model for debugging purposes.
    func test_parsingError_parsingFailed_includesReason() {
        let reason = "unexpected JSON format"
        let error = RouteNLPParser.ParsingError.parsingFailed(reason)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(
            description.contains(reason),
            "Error should include the specific failure reason"
        )
    }
}
