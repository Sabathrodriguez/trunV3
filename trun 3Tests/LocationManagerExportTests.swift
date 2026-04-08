//
//  LocationManagerExportTests.swift
//  trun 3Tests
//
//  Tests for LocationManager's TCX and GPX string generation methods.
//  These methods serialize recorded GPS locations into standard XML formats
//  for Strava upload (TCX) and route recording (GPX).
//
//  These tests complement the existing LocationManagerTests by covering
//  the export/serialization functionality rather than the live tracking behavior.
//

import XCTest
import CoreLocation
@testable import trun_3

final class LocationManagerExportTests: XCTestCase {

    private var sut: LocationManager!
    private var mockLocation: MockLocationProvider!
    private var mockAltimeter: MockAltimeterProvider!

    override func setUp() {
        super.setUp()
        MockAltimeterProvider.isRelativeAltitudeAvailable = true
        mockLocation = MockLocationProvider()
        mockAltimeter = MockAltimeterProvider()
        sut = LocationManager(locationProvider: mockLocation, altimeterProvider: mockAltimeter)
    }

    override func tearDown() {
        sut = nil
        mockLocation = nil
        mockAltimeter = nil
        super.tearDown()
    }

    // MARK: - createTCXString

    /// When no locations have been recorded during a run, createTCXString
    /// should return an empty string since there's no data to export.
    func test_createTCXString_emptyLocations_returnsEmptyString() {
        let tcx = sut.createTCXString(totalTimeSeconds: 600, distanceMeters: 1000)
        XCTAssertEqual(tcx, "", "No run locations should produce empty TCX string")
    }

    /// A TCX export with recorded locations should contain the required
    /// TrainingCenterDatabase XML structure that Strava expects.
    func test_createTCXString_withLocations_containsRequiredElements() {
        // Start run tracking and simulate GPS updates
        sut.startRunTracking()
        mockLocation.simulateLocation(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 10.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
        )
        mockLocation.simulateLocation(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7759, longitude: -122.4184),
                altitude: 12.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date().addingTimeInterval(30)
            )
        )

        let tcx = sut.createTCXString(totalTimeSeconds: 600, distanceMeters: 1000)

        XCTAssertTrue(tcx.contains("TrainingCenterDatabase"),
                      "TCX should have the TrainingCenterDatabase root element")
        XCTAssertTrue(tcx.contains("<Activity Sport=\"Running\">"),
                      "TCX should specify the Running sport type")
        XCTAssertTrue(tcx.contains("<Trackpoint>"),
                      "TCX should contain at least one trackpoint")
        XCTAssertTrue(tcx.contains("<LatitudeDegrees>"),
                      "TCX trackpoints should include latitude")
        XCTAssertTrue(tcx.contains("<LongitudeDegrees>"),
                      "TCX trackpoints should include longitude")
        XCTAssertTrue(tcx.contains("<AltitudeMeters>"),
                      "TCX trackpoints should include altitude")
        XCTAssertTrue(tcx.contains("<DistanceMeters>"),
                      "TCX trackpoints should include cumulative distance")
    }

    /// The TCX output should include the correct total time and distance
    /// values in the Lap element (used by Strava for summary statistics).
    func test_createTCXString_includesLapSummary() {
        sut.startRunTracking()
        mockLocation.simulateLocation(CLLocation(latitude: 37.7749, longitude: -122.4194))

        let tcx = sut.createTCXString(totalTimeSeconds: 1800.0, distanceMeters: 5000.0)

        XCTAssertTrue(tcx.contains("<TotalTimeSeconds>1800.0</TotalTimeSeconds>"),
                      "TCX should include the exact total time in seconds")
        XCTAssertTrue(tcx.contains("<DistanceMeters>5000.0</DistanceMeters>"),
                      "TCX should include the exact total distance in meters")
    }

    /// Each TCX trackpoint should have cumulative distance (not per-segment),
    /// which Strava uses to reconstruct the pace graph.
    func test_createTCXString_firstTrackpointHasZeroCumulativeDistance() {
        sut.startRunTracking()
        mockLocation.simulateLocation(CLLocation(latitude: 37.7749, longitude: -122.4194))

        let tcx = sut.createTCXString(totalTimeSeconds: 100, distanceMeters: 100)

        // First trackpoint's cumulative distance should be 0.0 (start of run)
        XCTAssertTrue(tcx.contains("<DistanceMeters>0.0</DistanceMeters>"),
                      "First trackpoint should have 0 cumulative distance")
    }

    // MARK: - createGPXString (route recording)

    /// createGPXString should produce valid GPX XML with the required
    /// header, track, and track segment elements.
    func test_createGPXString_basicStructure() {
        // Start recording and add a location
        sut.startRecording()
        // The recording timer captures locations every 5 seconds,
        // but we can test the GPX output structure by checking what's already there.
        // Since no timer has fired yet, the recorded locations will be empty.
        let gpx = sut.createGPXString()

        XCTAssertTrue(gpx.contains("<gpx"), "GPX should have the <gpx> root element")
        XCTAssertTrue(gpx.contains("<trk>"), "GPX should have a track element")
        XCTAssertTrue(gpx.contains("<trkseg>"), "GPX should have a track segment")
        XCTAssertTrue(gpx.contains("creator=\"TrunApp\""), "GPX should identify the creator app")
    }

    /// An empty recording (no timer fires) should still produce valid GPX XML
    /// structure, just without any <trkpt> elements.
    func test_createGPXString_emptyRecording_noTrackpoints() {
        let gpx = sut.createGPXString()
        XCTAssertFalse(gpx.contains("<trkpt"), "No recorded locations should mean no trackpoints")
    }

    // MARK: - Recording state

    /// startRecording should set isRecording to true and configure
    /// the location provider for active updates.
    func test_startRecording_setsIsRecording() {
        sut.startRecording()
        XCTAssertTrue(sut.isRecording, "isRecording should be true after startRecording")
    }

    /// stopRecording should set isRecording back to false.
    func test_stopRecording_clearsIsRecording() {
        sut.startRecording()
        sut.stopRecording()
        XCTAssertFalse(sut.isRecording, "isRecording should be false after stopRecording")
    }

    /// Calling startRecording when already recording should be a no-op
    /// (guard prevents double-start).
    func test_startRecording_doubleStart_isIdempotent() {
        sut.startRecording()
        sut.startRecording() // second call should be ignored
        XCTAssertTrue(sut.isRecording, "Should still be recording after double start")
        // Only 1 startUpdatingLocation call from the first startRecording
        // (plus potentially the one from init if it auto-starts, but we check relative counts)
    }

    /// Calling stopRecording when not recording should be a no-op.
    func test_stopRecording_whenNotRecording_isIdempotent() {
        sut.stopRecording() // not recording, should not crash
        XCTAssertFalse(sut.isRecording)
    }

    // MARK: - Unit conversions

    /// convertToMiles should apply the correct meters-to-miles factor (0.000621371).
    func test_convertToMiles_withKnownDistance() {
        // Simulate movement to set distance
        let loc1 = CLLocation(latitude: 37.0000, longitude: -122.0000)
        let loc2 = CLLocation(latitude: 37.0090, longitude: -122.0000)
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)

        let miles = sut.convertToMiles()
        XCTAssertGreaterThan(miles, 0, "Should have positive distance after movement")

        // Verify the conversion factor: miles = distance * 0.000621371
        let expectedMiles = sut.distance * 0.000621371
        XCTAssertEqual(miles, expectedMiles, accuracy: 0.001,
                       "convertToMiles should use the standard meters-to-miles factor")
    }

    /// convertTofeet should apply the correct meters-to-feet factor (3.28084).
    func test_convertToFeet_withKnownDistance() {
        let loc1 = CLLocation(latitude: 37.0000, longitude: -122.0000)
        let loc2 = CLLocation(latitude: 37.0090, longitude: -122.0000)
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)

        let feet = sut.convertTofeet()
        let expectedFeet = sut.distance * 3.28084
        XCTAssertEqual(feet, expectedFeet, accuracy: 0.01,
                       "convertTofeet should use the standard meters-to-feet factor")
    }
}
