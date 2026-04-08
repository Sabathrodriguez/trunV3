//
//  WaypointGeneratorTests.swift
//  trun 3Tests
//
//  Tests for WaypointGenerator — generates GPS waypoints for loop, out-and-back,
//  and point-to-point routes based on a start location, target distance, and
//  optional direction bias. The Google Routes API later snaps these waypoints
//  to real roads/paths.
//
//  Note: Some tests use seeded checks rather than exact values because the
//  generator uses Double.random for jitter and angle offsets when no bias is given.
//

import XCTest
import CoreLocation
@testable import trun_3

@available(iOS 26.0, *)
final class WaypointGeneratorTests: XCTestCase {

    private var sut: WaypointGenerator!
    private let sfCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    override func setUp() {
        super.setUp()
        sut = WaypointGenerator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a RouteRequest with the given parameters for testing.
    private func makeRequest(
        distance: Double = 3.0,
        type: RouteType = .loop,
        activity: ActivityType = .running
    ) -> RouteRequest {
        RouteRequest(
            targetDistanceMiles: distance,
            routeType: type,
            activityType: activity
        )
    }

    // MARK: - Loop waypoints

    /// A loop route should start and end at the same coordinate (the user's location).
    /// This is the defining characteristic of a loop — it returns to the start.
    func test_generateLoopWaypoints_startsAndEndsAtStart() {
        let waypoints = sut.generateLoopWaypoints(
            start: sfCenter,
            targetDistanceMiles: 3.0,
            biasToward: nil
        )
        XCTAssertGreaterThan(waypoints.count, 2, "Loop should have multiple intermediate waypoints")
        XCTAssertEqual(waypoints.first!.latitude, sfCenter.latitude, accuracy: 0.0001,
                       "Loop should start at the user's location")
        XCTAssertEqual(waypoints.last!.latitude, sfCenter.latitude, accuracy: 0.0001,
                       "Loop should end at the user's location (return to start)")
        XCTAssertEqual(waypoints.last!.longitude, sfCenter.longitude, accuracy: 0.0001)
    }

    /// Short loops (< 2 miles) should use 5 intermediate waypoints + start + end = 7 total.
    /// This matches the loopWaypointCount table in the implementation.
    func test_generateLoopWaypoints_shortDistance_uses5IntermediatePoints() {
        let waypoints = sut.generateLoopWaypoints(
            start: sfCenter,
            targetDistanceMiles: 1.5,
            biasToward: nil
        )
        // 1 start + 5 intermediate + 1 end = 7
        XCTAssertEqual(waypoints.count, 7, "Short loop (<2mi) should have 5 intermediate waypoints")
    }

    /// Medium loops (2–5 miles) should use 6 intermediate waypoints.
    func test_generateLoopWaypoints_mediumDistance_uses6IntermediatePoints() {
        let waypoints = sut.generateLoopWaypoints(
            start: sfCenter,
            targetDistanceMiles: 3.0,
            biasToward: nil
        )
        // 1 start + 6 intermediate + 1 end = 8
        XCTAssertEqual(waypoints.count, 8, "Medium loop (2-5mi) should have 6 intermediate waypoints")
    }

    /// Long loops (>= 5 miles) should use 8 intermediate waypoints for better
    /// route shape fidelity over the larger area.
    func test_generateLoopWaypoints_longDistance_uses8IntermediatePoints() {
        let waypoints = sut.generateLoopWaypoints(
            start: sfCenter,
            targetDistanceMiles: 7.0,
            biasToward: nil
        )
        // 1 start + 8 intermediate + 1 end = 10
        XCTAssertEqual(waypoints.count, 10, "Long loop (>=5mi) should have 8 intermediate waypoints")
    }

    /// When a direction bias is provided, waypoints should generally extend
    /// toward the bias coordinate rather than in a random direction.
    func test_generateLoopWaypoints_withBias_extendsTowardBias() {
        let northBias = CLLocationCoordinate2D(latitude: 37.9, longitude: -122.4194)
        let waypoints = sut.generateLoopWaypoints(
            start: sfCenter,
            targetDistanceMiles: 3.0,
            biasToward: northBias
        )

        // At least some intermediate waypoints should be north of the start
        let intermediates = waypoints.dropFirst().dropLast()
        let northernPoints = intermediates.filter { $0.latitude > sfCenter.latitude }
        XCTAssertGreaterThan(
            northernPoints.count, 0,
            "With a northern bias, some waypoints should be north of the start"
        )
    }

    // MARK: - Out and Back waypoints

    /// An out-and-back route should have exactly 3 points: start, turnaround, start.
    func test_generateOutAndBack_hasThreePoints() {
        let request = makeRequest(distance: 4.0, type: .outAndBack)
        let waypoints = sut.generateWaypoints(from: sfCenter, request: request)

        XCTAssertEqual(waypoints.count, 3, "Out-and-back should be: start → turnaround → start")
    }

    /// The first and last points of an out-and-back should be the start location.
    func test_generateOutAndBack_startsAndEndsAtStart() {
        let request = makeRequest(distance: 4.0, type: .outAndBack)
        let waypoints = sut.generateWaypoints(from: sfCenter, request: request)

        XCTAssertEqual(waypoints.first!.latitude, sfCenter.latitude, accuracy: 0.0001)
        XCTAssertEqual(waypoints.last!.latitude, sfCenter.latitude, accuracy: 0.0001)
    }

    /// The turnaround point should be roughly half the target distance from the start,
    /// since the user runs out half the distance and back the same way.
    func test_generateOutAndBack_turnaroundIsApproximatelyHalfDistance() {
        let targetMiles = 6.0
        let request = makeRequest(distance: targetMiles, type: .outAndBack)
        let waypoints = sut.generateWaypoints(from: sfCenter, request: request)

        // Turnaround is waypoints[1]
        let turnaround = CLLocation(latitude: waypoints[1].latitude, longitude: waypoints[1].longitude)
        let start = CLLocation(latitude: sfCenter.latitude, longitude: sfCenter.longitude)
        let distanceMiles = turnaround.distance(from: start) * 0.000621371

        // Should be approximately half of 6 miles = 3 miles (within 50% tolerance
        // because the degree-to-mile approximation isn't perfect)
        XCTAssertEqual(distanceMiles, 3.0, accuracy: 1.5,
                       "Turnaround should be roughly half the target distance from start")
    }

    // MARK: - Point to Point waypoints

    /// When a direction bias (destination) is provided for point-to-point,
    /// the waypoints should be just [start, destination].
    func test_generatePointToPoint_withDestination_hasTwoPoints() {
        let destination = CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4)
        let request = makeRequest(distance: 5.0, type: .pointToPoint)
        let waypoints = sut.generateWaypoints(
            from: sfCenter,
            request: request,
            directionBiasCoordinate: destination
        )

        XCTAssertEqual(waypoints.count, 2, "Point-to-point with destination should have exactly 2 points")
        XCTAssertEqual(waypoints[0].latitude, sfCenter.latitude, accuracy: 0.0001)
        XCTAssertEqual(waypoints[1].latitude, destination.latitude, accuracy: 0.0001)
    }

    /// When no destination is provided for point-to-point, the generator falls
    /// back to out-and-back behavior (3 waypoints).
    func test_generatePointToPoint_withoutDestination_fallsBackToOutAndBack() {
        let request = makeRequest(distance: 5.0, type: .pointToPoint)
        let waypoints = sut.generateWaypoints(from: sfCenter, request: request)

        XCTAssertEqual(waypoints.count, 3,
                       "Point-to-point without destination should fall back to out-and-back (3 points)")
    }

    // MARK: - generateWaypoints (dispatch)

    /// The main generateWaypoints method should dispatch to the correct
    /// sub-generator based on the route type.
    func test_generateWaypoints_dispatchesCorrectly_forLoop() {
        let request = makeRequest(type: .loop)
        let waypoints = sut.generateWaypoints(from: sfCenter, request: request)

        // Loop waypoints: start + intermediates + end (at least 7)
        XCTAssertGreaterThanOrEqual(waypoints.count, 7, "Loop dispatch should produce loop-style waypoints")
        XCTAssertEqual(waypoints.first!.latitude, waypoints.last!.latitude, accuracy: 0.0001,
                       "Loop should start and end at the same point")
    }

    // MARK: - adjustWaypoints

    /// adjustWaypoints scales all non-start waypoints relative to the start.
    /// A scale factor of 2.0 should double the distance of each waypoint from start.
    func test_adjustWaypoints_scaleUp() {
        let start = sfCenter
        let waypoints = [
            start,
            CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194),
            start
        ]

        let adjusted = sut.adjustWaypoints(waypoints, around: start, scaleFactor: 2.0)

        // The middle waypoint was 0.01 degrees from start, should now be 0.02
        let expectedLat = start.latitude + (37.7849 - start.latitude) * 2.0
        XCTAssertEqual(adjusted[1].latitude, expectedLat, accuracy: 0.0001,
                       "Scaled waypoint should be twice as far from start")
    }

    /// A scale factor of 0.5 should halve the distance of each waypoint from start.
    func test_adjustWaypoints_scaleDown() {
        let start = sfCenter
        let waypoints = [
            start,
            CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194),
            start
        ]

        let adjusted = sut.adjustWaypoints(waypoints, around: start, scaleFactor: 0.5)

        let expectedLat = start.latitude + (37.7849 - start.latitude) * 0.5
        XCTAssertEqual(adjusted[1].latitude, expectedLat, accuracy: 0.0001,
                       "Halved waypoint should be half as far from start")
    }

    /// Start points (same coordinates as start) should not be scaled — they
    /// should remain exactly at the start position.
    func test_adjustWaypoints_preservesStartPoints() {
        let start = sfCenter
        let waypoints = [
            start,
            CLLocationCoordinate2D(latitude: 37.79, longitude: -122.42),
            start
        ]

        let adjusted = sut.adjustWaypoints(waypoints, around: start, scaleFactor: 3.0)

        XCTAssertEqual(adjusted[0].latitude, start.latitude, accuracy: 0.00001,
                       "First point (start) should not be moved")
        XCTAssertEqual(adjusted[2].latitude, start.latitude, accuracy: 0.00001,
                       "Last point (start) should not be moved")
    }

    /// A scale factor of 1.0 should return waypoints unchanged.
    func test_adjustWaypoints_identityScale() {
        let start = sfCenter
        let mid = CLLocationCoordinate2D(latitude: 37.79, longitude: -122.42)
        let waypoints = [start, mid, start]

        let adjusted = sut.adjustWaypoints(waypoints, around: start, scaleFactor: 1.0)

        XCTAssertEqual(adjusted[1].latitude, mid.latitude, accuracy: 0.00001,
                       "Scale factor 1.0 should leave waypoints unchanged")
        XCTAssertEqual(adjusted[1].longitude, mid.longitude, accuracy: 0.00001)
    }
}
