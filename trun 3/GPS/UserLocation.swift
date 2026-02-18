//
//  UserLocation.swift
//  trun
//
//  Created by Sabath Rodriguez on 12/13/24.
//

import MapKit
import SwiftUI

final class UserLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    var locationManager: CLLocationManager?
    
    // ... existing publishers ...
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
    
    // Ensure this default includes 'followsHeading'
    @Published var regionView = MapCameraPosition.userLocation(followsHeading: true, fallback: .automatic)
    
    func checkIfLocationServicesEnabled() {
        if !CLLocationManager.locationServicesEnabled() {
            checkLocationAuthorization()
        } else {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        }
    }
    
    func checkLocationAuthorization() {
        guard let locationManager else { return }
        
        switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                regionView = .userLocation(followsHeading: true, fallback: .automatic)
                break
            case .denied, .restricted, .notDetermined:
                break
            @unknown default:
                break
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }
    
    // FIX 3: Add the delegate method to handle heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // We don't need to do anything with the value here,
        // but the method must exist for the manager to deliver the data to the Map system.
    }
    
    func centerOnUser() {
        // FIX 4: Explicitly re-engage heading tracking when recentering
        regionView = .userLocation(followsHeading: true, fallback: .automatic)
    }
}
