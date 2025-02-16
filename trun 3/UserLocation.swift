//
//  ContentViewModel.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/13/24.
//

import MapKit
import SwiftUI

final class UserLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    var locationManager: CLLocationManager?
    
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
    
    @Published var regionView = MapCameraPosition.userLocation(fallback: .automatic)
    
    func checkIfLocationServicesEnabled() {
        if !CLLocationManager.locationServicesEnabled() {
            //TODO: show an alert if services are not enabled
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
                region = MKCoordinateRegion(center: locationManager.location!.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                regionView = MapCameraPosition.region(MKCoordinateRegion(center: locationManager.location!.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
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
    
    func centerOnUser() {
            regionView = .userLocation(fallback: .automatic)
        }
}
