//
//  SharedRouteService.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

class SharedRouteService: ObservableObject {
    @Published var nearbyRoutes: [SharedRoute] = []
    @Published var allRoutes: [SharedRoute] = []
    @Published var searchResults: [SharedRoute] = []
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    /// Publish a route to the shared library with its center coordinates for geo-filtering.
    func publishRoute(name: String, gpxString: String, distanceMiles: Double, coordinates: [CLLocationCoordinate2D]) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[DEBUG] publishRoute failed: No authenticated user (currentUser is nil)")
            return
        }
        guard !coordinates.isEmpty else {
            print("[DEBUG] publishRoute failed: coordinates array is empty")
            return
        }
        print("[DEBUG] publishRoute: uid=\(uid), name=\(name), coords=\(coordinates.count), distance=\(distanceMiles)")

        // Calculate center point (average of all coordinates)
        let centerLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
        let centerLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)

        let data: [String: Any] = [
            "uid": uid,
            "name": name,
            "distanceMiles": distanceMiles,
            "centerLat": centerLat,
            "centerLon": centerLon,
            "gpxData": gpxString,
            "createdAt": FieldValue.serverTimestamp(),
            "runCount": 0
        ]

        db.collection("sharedRoutes").addDocument(data: data) { error in
            if let error = error {
                print("Error publishing route: \(error)")
            }
        }
    }

    /// Fetch routes within ~10 miles of the user's current location.
    func fetchNearbyRoutes(userLat: Double, userLon: Double, radiusMiles: Double = 10, limit: Int = 30) {
        isLoading = true

        // ~0.0145 degrees latitude per mile, ~0.018 degrees longitude per mile at mid-latitudes
        let latDelta = radiusMiles * 0.0145
        let lonDelta = radiusMiles * 0.018

        db.collection("sharedRoutes")
            .whereField("centerLat", isGreaterThan: userLat - latDelta)
            .whereField("centerLat", isLessThan: userLat + latDelta)
            .limit(to: limit)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    self.isLoading = false
                }

                if let error = error {
                    print("Error fetching nearby routes: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                var routes: [SharedRoute] = []
                for doc in documents {
                    let data = doc.data()
                    let lon = data["centerLon"] as? Double ?? 0

                    // Client-side longitude filter (Firestore only supports range on one field)
                    guard lon > userLon - lonDelta && lon < userLon + lonDelta else { continue }

                    let timestamp = data["createdAt"] as? Timestamp
                    let route = SharedRoute(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Unnamed Route",
                        distanceMiles: data["distanceMiles"] as? Double ?? 0,
                        centerLat: data["centerLat"] as? Double ?? 0,
                        centerLon: lon,
                        runCount: data["runCount"] as? Int ?? 0,
                        createdAt: timestamp?.dateValue() ?? Date()
                    )
                    routes.append(route)
                }

                // Sort by popularity (most runs first)
                routes.sort { $0.runCount > $1.runCount }

                DispatchQueue.main.async {
                    self.nearbyRoutes = routes
                }
            }
    }

    /// Fetch all shared routes (no geo-filter) for database inspection.
    func fetchAllRoutes(limit: Int = 50) {
        isLoading = true

        db.collection("sharedRoutes")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async { self.isLoading = false }

                if let error = error {
                    print("Error fetching all routes: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let routes: [SharedRoute] = documents.compactMap { doc in
                    let data = doc.data()
                    let timestamp = data["createdAt"] as? Timestamp
                    return SharedRoute(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Unnamed Route",
                        distanceMiles: data["distanceMiles"] as? Double ?? 0,
                        centerLat: data["centerLat"] as? Double ?? 0,
                        centerLon: data["centerLon"] as? Double ?? 0,
                        runCount: data["runCount"] as? Int ?? 0,
                        createdAt: timestamp?.dateValue() ?? Date()
                    )
                }

                DispatchQueue.main.async { self.allRoutes = routes }
            }
    }

    /// Geocode a place name and fetch shared routes near that location.
    func searchRoutesByLocation(query: String) {
        isLoading = true
        searchResults = []

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
            guard let self = self else { return }

            if let error = error {
                print("Geocoding error: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let coordinate = placemarks?.first?.location?.coordinate else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let radiusMiles: Double = 25
            let latDelta = radiusMiles * 0.0145
            let lonDelta = radiusMiles * 0.018

            self.db.collection("sharedRoutes")
                .whereField("centerLat", isGreaterThan: coordinate.latitude - latDelta)
                .whereField("centerLat", isLessThan: coordinate.latitude + latDelta)
                .limit(to: 30)
                .getDocuments { [weak self] snapshot, error in
                    guard let self = self else { return }

                    if let error = error {
                        print("Error searching routes: \(error)")
                        DispatchQueue.main.async { self.isLoading = false }
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        DispatchQueue.main.async { self.isLoading = false }
                        return
                    }

                    var routes: [SharedRoute] = []
                    for doc in documents {
                        let data = doc.data()
                        let lon = data["centerLon"] as? Double ?? 0

                        guard lon > coordinate.longitude - lonDelta && lon < coordinate.longitude + lonDelta else { continue }

                        let timestamp = data["createdAt"] as? Timestamp
                        let route = SharedRoute(
                            id: doc.documentID,
                            name: data["name"] as? String ?? "Unnamed Route",
                            distanceMiles: data["distanceMiles"] as? Double ?? 0,
                            centerLat: data["centerLat"] as? Double ?? 0,
                            centerLon: lon,
                            runCount: data["runCount"] as? Int ?? 0,
                            createdAt: timestamp?.dateValue() ?? Date()
                        )
                        routes.append(route)
                    }

                    routes.sort { $0.runCount > $1.runCount }

                    DispatchQueue.main.async {
                        self.searchResults = routes
                        self.isLoading = false
                    }
                }
        }
    }

    /// Fetch the full GPX data for a specific shared route.
    func fetchRouteGPX(docID: String, completion: @escaping (String?) -> Void) {
        db.collection("sharedRoutes").document(docID).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching route GPX: \(error)")
                completion(nil)
                return
            }
            let gpxData = snapshot?.data()?["gpxData"] as? String
            completion(gpxData)
        }
    }
}
