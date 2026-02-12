//
//  LocationManager.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/21/24.
//

import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var distance: Double = 0
    private var previousLocation: CLLocation?
    
    @Published var heading: CLHeading?
    
    // Recording properties
    @Published var isRecording: Bool = false
    private var recordedLocations: [CLLocation] = []
    private var recordingTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness // Indicate activity type
        locationManager.distanceFilter = 10
        
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        requestAuthorization()
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization() // Or requestAlwaysAuthorization for background tracking
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location

        // Handle the first location update
        guard let lastLocation = previousLocation else {
            previousLocation = location
            return
        }

        // Check distance from the LAST RECORDED location
        let delta = location.distance(from: lastLocation)
        
        // Only update if we moved enough
        if delta > locationManager.distanceFilter {
            distance += delta
            previousLocation = location // <--- MOVE THIS INSIDE THE IF BLOCK
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
