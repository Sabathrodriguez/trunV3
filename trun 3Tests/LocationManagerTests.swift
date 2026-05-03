//
//  LocationManagerTests.swift
//  trun 3Tests
//

import XCTest
import CoreLocation
import CoreMotion
@testable import trun_3

// MARK: - MockLocationProvider

final class MockLocationProvider: LocationProvider {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var allowsBackgroundLocationUpdates: Bool = false
    var pausesLocationUpdatesAutomatically: Bool = true
    var showsBackgroundLocationIndicator: Bool = false
    var activityType: CLActivityType = .other

    private(set) var startUpdatingLocationCount = 0
    private(set) var stopUpdatingLocationCount = 0
    private(set) var startUpdatingHeadingCount = 0
    private(set) var stopUpdatingHeadingCount = 0
    private(set) var requestWhenInUseCount = 0
    private(set) var requestAlwaysCount = 0

    func requestWhenInUseAuthorization() { requestWhenInUseCount += 1 }
    func requestAlwaysAuthorization() { requestAlwaysCount += 1 }
    func startUpdatingLocation() { startUpdatingLocationCount += 1 }
    func stopUpdatingLocation() { stopUpdatingLocationCount += 1 }
    func startUpdatingHeading() { startUpdatingHeadingCount += 1 }
    func stopUpdatingHeading() { stopUpdatingHeadingCount += 1 }

    /// Simulate a GPS location update arriving from the system.
    func simulateLocation(_ location: CLLocation) {
        delegate?.locationManager?(CLLocationManager(), didUpdateLocations: [location])
    }
}

// MARK: - MockAltimeterProvider

final class MockAltimeterProvider: AltimeterProvider {
    static var isRelativeAltitudeAvailable: Bool = true

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAltitudeHandler) {
        startCount += 1
    }

    func stopRelativeAltitudeUpdates() {
        stopCount += 1
    }
}

// MARK: - LocationManagerTests

final class LocationManagerTests: XCTestCase {

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

    // MARK: - Initial state

    func test_initialDistance_isZero() {
        XCTAssertEqual(sut.distance, 0)
    }

    func test_initialRunLocations_isEmpty() {
        XCTAssertTrue(sut.runLocations.isEmpty)
    }

    func test_initialElevationGain_isZero() {
        XCTAssertEqual(sut.elevationGain, 0)
    }

    func test_initialIsRecording_isFalse() {
        XCTAssertFalse(sut.isRecording)
    }

    func test_init_requestsWhenInUseAuthorization() {
        XCTAssertEqual(mockLocation.requestWhenInUseCount, 1)
    }

    // MARK: - startTracking / stopTracking

    func test_startTracking_startsLocationAndHeading() {
        sut.startTracking()
        XCTAssertEqual(mockLocation.startUpdatingLocationCount, 1)
        XCTAssertEqual(mockLocation.startUpdatingHeadingCount, 1)
    }

    func test_stopTracking_stopsLocationAndHeading() {
        sut.startTracking()
        sut.stopTracking()
        XCTAssertEqual(mockLocation.stopUpdatingLocationCount, 1)
        XCTAssertEqual(mockLocation.stopUpdatingHeadingCount, 1)
    }

    func test_stopTracking_resetsDistance() {
        // Simulate two locations far enough apart to accumulate distance
        let loc1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let loc2 = CLLocation(latitude: 37.7849, longitude: -122.4194) // ~1.1 km north
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)
        XCTAssertGreaterThan(sut.distance, 0)

        sut.stopTracking()
        XCTAssertEqual(sut.distance, 0)
    }

    func test_pauseTracking_stopsLocationUpdates() {
        sut.startTracking()
        sut.pauseTracking()
        XCTAssertEqual(mockLocation.stopUpdatingLocationCount, 1)
    }

    // MARK: - Distance accumulation

    func test_locationUpdate_accumulates_distanceAboveThreshold() {
        let loc1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let loc2 = CLLocation(latitude: 37.7849, longitude: -122.4194) // ~1.1 km north
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)
        XCTAssertGreaterThan(sut.distance, 0)
    }

    func test_locationUpdate_ignores_movementBelowThreshold() {
        let loc1 = CLLocation(latitude: 37.7749000, longitude: -122.4194000)
        // Move only ~1 metre — below the 10 m threshold
        let loc2 = CLLocation(latitude: 37.7749090, longitude: -122.4194000)
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)
        XCTAssertEqual(sut.distance, 0)
    }

    func test_locationUpdate_setsCurrentLocation() {
        let loc = CLLocation(latitude: 37.7749, longitude: -122.4194)
        mockLocation.simulateLocation(loc)
        XCTAssertEqual(sut.location?.coordinate.latitude ?? 0, 37.7749, accuracy: 0.0001)
    }

    // MARK: - Run tracking

    func test_startRunTracking_clearsRunLocations() {
        // Pre-populate via a location update while run is active
        sut.startRunTracking()
        mockLocation.simulateLocation(CLLocation(latitude: 37.7749, longitude: -122.4194))
        sut.stopRunTracking()

        sut.startRunTracking() // second start should reset
        XCTAssertTrue(sut.runLocations.isEmpty)
    }

    func test_startRunTracking_resetsElevationGain() {
        sut.startRunTracking()
        XCTAssertEqual(sut.elevationGain, 0)
    }

    func test_startRunTracking_setsDistanceFilterToNone() {
        sut.startRunTracking()
        XCTAssertEqual(mockLocation.distanceFilter, kCLDistanceFilterNone)
    }

    func test_startRunTracking_startsAltimeter_whenAvailable() {
        sut.startRunTracking()
        XCTAssertEqual(mockAltimeter.startCount, 1)
    }

    func test_startRunTracking_doesNotStartAltimeter_whenUnavailable() {
        MockAltimeterProvider.isRelativeAltitudeAvailable = false
        let sut2 = LocationManager(locationProvider: MockLocationProvider(), altimeterProvider: mockAltimeter)
        sut2.startRunTracking()
        XCTAssertEqual(mockAltimeter.startCount, 0)
    }

    func test_stopRunTracking_stopsAltimeter() {
        sut.startRunTracking()
        sut.stopRunTracking()
        XCTAssertEqual(mockAltimeter.stopCount, 1)
    }

    func test_stopRunTracking_restoresDistanceFilter() {
        sut.startRunTracking()
        sut.stopRunTracking()
        XCTAssertEqual(mockLocation.distanceFilter, 10)
    }

    func test_locationsDuringRun_appendedToRunLocations() {
        sut.startRunTracking()
        mockLocation.simulateLocation(CLLocation(latitude: 37.7749, longitude: -122.4194))
        mockLocation.simulateLocation(CLLocation(latitude: 37.7849, longitude: -122.4194))
        XCTAssertEqual(sut.runLocations.count, 2)
    }

    func test_locationsOutsideRun_notAppendedToRunLocations() {
        mockLocation.simulateLocation(CLLocation(latitude: 37.7749, longitude: -122.4194))
        XCTAssertTrue(sut.runLocations.isEmpty)
    }

    // MARK: - resumeRunTracking

    func test_resumeRunTracking_restoresLocations() {
        let locs = [CLLocation(latitude: 37.7749, longitude: -122.4194),
                    CLLocation(latitude: 37.7849, longitude: -122.4194)]
        sut.resumeRunTracking(existingLocations: locs, existingDistance: 500, existingElevation: 10)
        XCTAssertEqual(sut.runLocations.count, 2)
    }

    func test_resumeRunTracking_restoresDistance() {
        sut.resumeRunTracking(existingLocations: [], existingDistance: 1234.5, existingElevation: 0)
        XCTAssertEqual(sut.distance, 1234.5, accuracy: 0.01)
    }

    func test_resumeRunTracking_restoresElevationGain() {
        sut.resumeRunTracking(existingLocations: [], existingDistance: 0, existingElevation: 42.0)
        XCTAssertEqual(sut.elevationGain, 42.0, accuracy: 0.01)
    }

    func test_resumeRunTracking_setsDistanceFilterToNone() {
        sut.resumeRunTracking(existingLocations: [], existingDistance: 0, existingElevation: 0)
        XCTAssertEqual(mockLocation.distanceFilter, kCLDistanceFilterNone)
    }

    // MARK: - Unit conversion

    func test_convertToMiles_correctFactor() {
        // Simulate enough movement to get a known distance
        let loc1 = CLLocation(latitude: 37.0000, longitude: -122.0000)
        let loc2 = CLLocation(latitude: 37.0090, longitude: -122.0000) // ~1000 m north
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(loc2)

        let miles = sut.convertToMiles()
        let feet = sut.convertTofeet()
        XCTAssertGreaterThan(miles, 0)
        XCTAssertGreaterThan(feet, 0)
        // miles and feet should be consistent: 1 mile = 5280 feet
        XCTAssertEqual(miles * 5280, feet, accuracy: 1.0)
    }

    // MARK: - Stale location rejection

    func test_staleLocation_isRejected() {
        let staleDate = Date(timeIntervalSinceNow: -15)
        let staleLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: staleDate
        )
        mockLocation.simulateLocation(staleLoc)
        XCTAssertNil(sut.location)
    }

    func test_freshLocation_isAccepted() {
        let freshLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(freshLoc)
        XCTAssertNotNil(sut.location)
    }

    // MARK: - Accuracy filtering

    func test_inaccurateLocation_storedInRunLocations_butNotDistance() {
        sut.startRunTracking()
        let goodLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        let badLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7949, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 200, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(goodLoc)
        mockLocation.simulateLocation(badLoc)

        XCTAssertEqual(sut.runLocations.count, 2)
        XCTAssertEqual(sut.distance, 0)
    }

    func test_distanceResumes_fromLastAccurateLocation() {
        sut.startRunTracking()
        let loc1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        let badLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 200, verticalAccuracy: -1, timestamp: Date()
        )
        let loc2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(loc1)
        mockLocation.simulateLocation(badLoc)
        mockLocation.simulateLocation(loc2)

        let expectedDistance = loc2.distance(from: loc1)
        XCTAssertEqual(sut.distance, expectedDistance, accuracy: 1.0)
    }

    func test_negativeAccuracy_skipsDistance() {
        sut.startRunTracking()
        let goodLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        let invalidLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7949, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(goodLoc)
        mockLocation.simulateLocation(invalidLoc)

        XCTAssertEqual(sut.distance, 0)
        XCTAssertEqual(sut.runLocations.count, 2)
    }

    // MARK: - Signal watchdog state

    func test_startRunTracking_initializesSignalState() {
        sut.startRunTracking()
        XCTAssertNotNil(sut.lastLocationTimestamp)
        XCTAssertFalse(sut.isSignalLost)
    }

    func test_stopRunTracking_clearsSignalState() {
        sut.startRunTracking()
        sut.stopRunTracking()
        XCTAssertNil(sut.lastLocationTimestamp)
        XCTAssertFalse(sut.isSignalLost)
    }

    func test_locationUpdate_updatesLastLocationTimestamp() {
        sut.startRunTracking()
        let before = sut.lastLocationTimestamp!
        Thread.sleep(forTimeInterval: 0.05)

        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(loc)

        XCTAssertGreaterThan(sut.lastLocationTimestamp!, before)
    }

    // MARK: - Error callback

    func test_didFailWithError_callsOnLocationError_duringRun() {
        sut.startRunTracking()
        var receivedError: Error?
        sut.onLocationError = { error in receivedError = error }

        let error = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
        sut.locationManager(CLLocationManager(), didFailWithError: error)

        XCTAssertNotNil(receivedError)
    }

    func test_didFailWithError_doesNotCallCallback_outsideRun() {
        var receivedError: Error?
        sut.onLocationError = { error in receivedError = error }

        let error = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
        sut.locationManager(CLLocationManager(), didFailWithError: error)

        XCTAssertNil(receivedError)
    }

    // MARK: - onRunDistanceChanged fires for inaccurate locations

    func test_inaccurateLocation_stillFiresDistanceCallback() {
        sut.startRunTracking()
        let goodLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(goodLoc)

        var callbackFired = false
        sut.onRunDistanceChanged = { _ in callbackFired = true }

        let badLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7949, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: 200, verticalAccuracy: -1, timestamp: Date()
        )
        mockLocation.simulateLocation(badLoc)

        XCTAssertTrue(callbackFired)
    }
}
