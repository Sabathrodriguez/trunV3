//
//  LocationManager.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/21/24.
//

import SwiftUI
import CoreLocation
import CoreMotion

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
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
    private let altimeter = CMAltimeter()
    @Published var elevationGain: Double = 0 // meters
    private var lastRelativeAltitude: Double?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness // Indicate activity type
        locationManager.distanceFilter = 10
        
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        requestAuthorization()
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization() // Or requestAlwaysAuthorization for background tracking
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
                print("[LocationManager] Run location #\(runLocations.count) — accuracy: \(location.horizontalAccuracy)m")
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
    
    func startTracking(){
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        distance = 0
        previousLocation = nil
    }
    
    func pauseTracking() {
        locationManager.stopUpdatingLocation()
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
        // This gives HealthKit and Strava a dense route trace
        locationManager.distanceFilter = kCLDistanceFilterNone
        print("[LocationManager] Run tracking started — distanceFilter=\(locationManager.distanceFilter)")

        // Start barometric altimeter for accurate elevation tracking
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
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
        altimeter.stopRelativeAltitudeUpdates()
        print("[LocationManager] Run tracking stopped — captured \(runLocations.count) locations, elevation gain: \(String(format: "%.1f", elevationGain))m")
        // Restore distance filter for normal map usage (saves battery)
        locationManager.distanceFilter = 10
    }

    /// Resume run tracking from a recovered snapshot without resetting existing data.
    func resumeRunTracking(existingLocations: [CLLocation], existingDistance: Double, existingElevation: Double) {
        runLocations = existingLocations
        distance = existingDistance
        elevationGain = existingElevation
        previousLocation = existingLocations.last
        isRunActive = true
        locationManager.distanceFilter = kCLDistanceFilterNone
        print("[LocationManager] Run tracking resumed — restored \(existingLocations.count) locations, \(String(format: "%.1f", existingElevation))m elevation")

        // Restart altimeter (continues accumulating from restored elevationGain)
        if CMAltimeter.isRelativeAltitudeAvailable() {
            lastRelativeAltitude = nil
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
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
        
        // Clear previous data
        recordedLocations = []
        isRecording = true
        
        // Ensure location updates are active
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading( )
        
        // Capture location every 5 seconds
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let currentLocation = self.location else { return }
            self.recordedLocations.append(currentLocation)
            print("Recorded GPX point: \(currentLocation.coordinate)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        // We generally keep updating location for the map, but you could stop if desired:
        // locationManager.stopUpdatingLocation()
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
