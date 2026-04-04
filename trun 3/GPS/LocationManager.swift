//
//  LocationManager.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/21/24.
//

import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - Protocols (enable DI for unit testing)

/// Abstracts CLLocationManager so tests can inject a mock.
protocol LocationProvider: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }
    var activityType: CLActivityType { get set }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startUpdatingHeading()
    func stopUpdatingHeading()
}

extension CLLocationManager: LocationProvider {}

/// Abstracts CMAltimeter so tests can inject a mock.
protocol AltimeterProvider {
    static var isRelativeAltitudeAvailable: Bool { get }
    func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAltitudeHandler)
    func stopRelativeAltitudeUpdates()
}

extension CMAltimeter: AltimeterProvider {
    static var isRelativeAltitudeAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
}

// MARK: - LocationManager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationProvider: LocationProvider
    private let altimeterProvider: AltimeterProvider

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var distance: Double = 0
    private var previousLocation: CLLocation?
    private let distanceThreshold: Double = 10 // meters — minimum movement to count toward distance

    @Published var heading: CLHeading?

    // Recording properties (for route recording)
    @Published var isRecording: Bool = false
    private var recordedLocations: [CLLocation] = []
    private var recordingTimer: Timer?

    // Run tracking properties (for Strava export)
    private var isRunActive: Bool = false
    private(set) var runLocations: [CLLocation] = []

    // Elevation tracking (barometric altimeter)
    @Published var elevationGain: Double = 0 // meters
    private var lastRelativeAltitude: Double?

    init(
        locationProvider: LocationProvider = CLLocationManager(),
        altimeterProvider: AltimeterProvider = CMAltimeter()
    ) {
        self.locationProvider = locationProvider
        self.altimeterProvider = altimeterProvider
        super.init()
        locationProvider.delegate = self
        locationProvider.desiredAccuracy = kCLLocationAccuracyBest
        locationProvider.activityType = .fitness
        locationProvider.distanceFilter = 10
        locationProvider.allowsBackgroundLocationUpdates = true
        locationProvider.pausesLocationUpdatesAutomatically = false
        locationProvider.showsBackgroundLocationIndicator = true
        requestAuthorization()
    }

    func requestAuthorization() {
        locationProvider.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location

        // Capture every location for route tracking (HealthKit route + Strava TCX)
        if isRunActive {
            runLocations.append(location)
            if runLocations.count % 10 == 1 {
                AppLogger.location.debug("Run location #\(self.runLocations.count) — accuracy: \(location.horizontalAccuracy)m")
            }
        }

        // Handle the first location update
        guard let lastLocation = previousLocation else {
            previousLocation = location
            return
        }

        // Check distance from the LAST RECORDED location
        let delta = location.distance(from: lastLocation)

        // Only update distance counter if we moved enough (filters GPS jitter)
        if delta > distanceThreshold {
            distance += delta
            previousLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading
    }

    func startTracking() {
        locationProvider.startUpdatingLocation()
        locationProvider.startUpdatingHeading()
    }

    func stopTracking() {
        locationProvider.stopUpdatingLocation()
        locationProvider.stopUpdatingHeading()
        distance = 0
        previousLocation = nil
    }

    func pauseTracking() {
        locationProvider.stopUpdatingLocation()
    }

    func convertTofeet() -> Double {
        return distance * 3.28084
    }

    func convertToMiles() -> Double {
        return distance * 0.000621371
    }

    // MARK: - Run Tracking (for Strava export)

    func startRunTracking() {
        runLocations = []
        isRunActive = true
        elevationGain = 0
        lastRelativeAltitude = nil
        // Remove distance filter so iOS delivers locations at full frequency (~1/sec)
        locationProvider.distanceFilter = kCLDistanceFilterNone
        AppLogger.location.info("Run tracking started — distanceFilter=\(self.locationProvider.distanceFilter)")

        // Start barometric altimeter for accurate elevation tracking
        if type(of: altimeterProvider).isRelativeAltitudeAvailable {
            altimeterProvider.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                let currentAltitude = data.relativeAltitude.doubleValue // meters
                if let lastAlt = self.lastRelativeAltitude {
                    let delta = currentAltitude - lastAlt
                    if delta > 0 {
                        self.elevationGain += delta
                    }
                }
                self.lastRelativeAltitude = currentAltitude
            }
        }
    }

    func stopRunTracking() {
        isRunActive = false
        altimeterProvider.stopRelativeAltitudeUpdates()
        AppLogger.location.info("Run tracking stopped — \(self.runLocations.count) locations, elevation gain: \(String(format: "%.1f", self.elevationGain))m")
        // Restore distance filter for normal map usage (saves battery)
        locationProvider.distanceFilter = 10
    }

    /// Resume run tracking from a recovered snapshot without resetting existing data.
    func resumeRunTracking(existingLocations: [CLLocation], existingDistance: Double, existingElevation: Double) {
        runLocations = existingLocations
        distance = existingDistance
        elevationGain = existingElevation
        previousLocation = existingLocations.last
        isRunActive = true
        locationProvider.distanceFilter = kCLDistanceFilterNone
        AppLogger.location.info("Run tracking resumed — restored \(existingLocations.count) locations, \(String(format: "%.1f", existingElevation))m elevation")

        // Restart altimeter (continues accumulating from restored elevationGain)
        if type(of: altimeterProvider).isRelativeAltitudeAvailable {
            lastRelativeAltitude = nil
            altimeterProvider.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                let currentAltitude = data.relativeAltitude.doubleValue
                if let lastAlt = self.lastRelativeAltitude {
                    let delta = currentAltitude - lastAlt
                    if delta > 0 { self.elevationGain += delta }
                }
                self.lastRelativeAltitude = currentAltitude
            }
        }
    }

    // MARK: - GPX Recording

    func startRecording() {
        guard !isRecording else { return }

        recordedLocations = []
        isRecording = true

        locationProvider.startUpdatingLocation()
        locationProvider.startUpdatingHeading()

        // Capture location every 5 seconds
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let currentLocation = self.location else { return }
            self.recordedLocations.append(currentLocation)
            AppLogger.location.debug("Recorded GPX point: lat=\(currentLocation.coordinate.latitude), lon=\(currentLocation.coordinate.longitude)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    func createTCXString(totalTimeSeconds: Double, distanceMeters: Double) -> String {
        let dateFormatter = ISO8601DateFormatter()

        guard let firstLoc = runLocations.first else { return "" }
        let startTime = dateFormatter.string(from: firstLoc.timestamp)

        var tcx = """
<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>\(startTime)</Id>
      <Lap StartTime="\(startTime)">
        <TotalTimeSeconds>\(totalTimeSeconds)</TotalTimeSeconds>
        <DistanceMeters>\(distanceMeters)</DistanceMeters>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
"""

        var cumulativeDistance = 0.0
        var previousLoc: CLLocation?

        for loc in runLocations {
            if let prev = previousLoc {
                cumulativeDistance += loc.distance(from: prev)
            }
            previousLoc = loc

            let time = dateFormatter.string(from: loc.timestamp)
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let alt = loc.altitude

            tcx += """
          <Trackpoint>
            <Time>\(time)</Time>
            <Position>
              <LatitudeDegrees>\(lat)</LatitudeDegrees>
              <LongitudeDegrees>\(lon)</LongitudeDegrees>
            </Position>
            <AltitudeMeters>\(alt)</AltitudeMeters>
            <DistanceMeters>\(cumulativeDistance)</DistanceMeters>
          </Trackpoint>
"""
        }

        tcx += """
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>
"""

        return tcx
    }

    func createGPXString() -> String {
        let dateFormatter = ISO8601DateFormatter()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrunApp" xmlns="http://www.topografix.com/GPX/1/1">
            <trk>
                <name>Recorded Run</name>
                <trkseg>
        """

        for loc in recordedLocations {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let ele = loc.altitude
            let time = dateFormatter.string(from: loc.timestamp)

            gpx += """

                    <trkpt lat="\(lat)" lon="\(lon)">
                        <ele>\(ele)</ele>
                        <time>\(time)</time>
                    </trkpt>
            """
        }

        gpx += """

                </trkseg>
            </trk>
        </gpx>
        """

        return gpx
    }
}

