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
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    /// Publish a route to the shared library with its center coordinates for geo-filtering.
    func publishRoute(name: String, gpxString: String, distanceMiles: Double, coordinates: [CLLocationCoordinate2D]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !coordinates.isEmpty else { return }

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
