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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness // Indicate activity type
        locationManager.distanceFilter = 10
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

        if let previousLocation = previousLocation {
            if (location.distance(from: previousLocation) > locationManager.distanceFilter) {
                print("previous location: \(previousLocation)")
                print("new locatoin: \(location)")
                print("distance from previous: \(location.distance(from: previousLocation))")
                let delta = location.distance(from: previousLocation)
                distance += delta
            }
        }
        previousLocation = location
    }
    
    func startTracking(){
        locationManager.startUpdatingLocation()
    }
    
    func stopTracking(){
        locationManager.stopUpdatingLocation()
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
    
}
