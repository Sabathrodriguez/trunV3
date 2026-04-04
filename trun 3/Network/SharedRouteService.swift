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

    enum PublishError: LocalizedError {
        case duplicateRoute(String)
        case notAuthenticated
        case invalidData(String)

        var errorDescription: String? {
            switch self {
            case .duplicateRoute(let name):
                return "A route named \"\(name)\" with a similar distance already exists."
            case .notAuthenticated:
                return "You must be signed in to share routes."
            case .invalidData(let reason):
                return reason
            }
        }
    }

    /// Check if a route with the same name (case-insensitive) and similar distance already exists.
    private func checkForDuplicate(name: String, distanceMiles: Double, completion: @escaping (Bool) -> Void) {
        let nameLower = name.lowercased()

        db.collection("sharedRoutes")
            .whereField("nameLower", isEqualTo: nameLower)
            .getDocuments { snapshot, error in
                if let error = error {
                    AppLogger.routes.error("Error checking for duplicate route: \(error)")
                    completion(false)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(false)
                    return
                }

                let isDuplicate = documents.contains { doc in
                    let existingDistance = doc.data()["distanceMiles"] as? Double ?? 0
                    return abs(existingDistance - distanceMiles) <= 0.5
                }

                completion(isDuplicate)
            }
    }

    /// Publish a route to the shared library with its center coordinates for geo-filtering.
    /// Returns the Firestore document ID on success so callers can link the route locally.
    func publishRoute(name: String, gpxString: String, distanceMiles: Double, coordinates: [CLLocationCoordinate2D], completion: @escaping (Result<String, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.routes.error("publishRoute failed: No authenticated user (currentUser is nil)")
            completion(.failure(PublishError.notAuthenticated))
            return
        }
        guard !coordinates.isEmpty else {
            AppLogger.routes.error("publishRoute failed: coordinates array is empty")
            completion(.failure(PublishError.invalidData("No coordinates found.")))
            return
        }

        // Server-side validation before writing to Firestore
        guard gpxString.utf8.count <= GPXValidator.maxFileSizeBytes else {
            AppLogger.routes.error("publishRoute failed: GPX data too large (\(gpxString.utf8.count) bytes)")
            completion(.failure(PublishError.invalidData("GPX data is too large.")))
            return
        }
        guard coordinates.count <= GPXValidator.maxCoordinateCount else {
            AppLogger.routes.error("publishRoute failed: too many coordinates (\(coordinates.count))")
            completion(.failure(PublishError.invalidData("Too many coordinates.")))
            return
        }
        guard distanceMiles <= GPXValidator.maxDistanceMiles else {
            AppLogger.routes.error("publishRoute failed: route too long (\(distanceMiles) miles)")
            completion(.failure(PublishError.invalidData("Route is too long.")))
            return
        }

        // Check for duplicate before publishing
        checkForDuplicate(name: name, distanceMiles: distanceMiles) { [weak self] isDuplicate in
            guard let self = self else { return }

            if isDuplicate {
                DispatchQueue.main.async {
                    completion(.failure(PublishError.duplicateRoute(name)))
                }
                return
            }

            AppLogger.routes.info("publishRoute: uid=\(uid), name=\(name), coords=\(coordinates.count), distance=\(distanceMiles)")

            // Calculate center point (average of all coordinates)
            let centerLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
            let centerLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)

            let data: [String: Any] = [
                "uid": uid,
                "name": name,
                "nameLower": name.lowercased(),
                "distanceMiles": distanceMiles,
                "centerLat": centerLat,
                "centerLon": centerLon,
                "gpxData": gpxString,
                "createdAt": FieldValue.serverTimestamp(),
                "runCount": 0
            ]

            var ref: DocumentReference? = nil
            ref = self.db.collection("sharedRoutes").addDocument(data: data) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppLogger.routes.error("Error publishing route: \(error)")
                        completion(.failure(error))
                    } else {
                        SharedRouteCacheService.clear()
                        completion(.success(ref!.documentID))
                    }
                }
            }
        }
    }

    /// Fetch routes within ~10 miles of the user's current location.
    /// Checks local cache first; falls back to Firestore if cache is stale or user moved.
    func fetchNearbyRoutes(userLat: Double, userLon: Double, radiusMiles: Double = 10, limit: Int = 30, forceRefresh: Bool = false) {

        // Check cache first (unless force refresh)
        if !forceRefresh,
           let cache = SharedRouteCacheService.load(),
           SharedRouteCacheService.isValid(cache: cache, currentLat: userLat, currentLon: userLon) {
            self.nearbyRoutes = cache.routes
            return
        }

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
                    AppLogger.routes.error("Error fetching nearby routes: \(error)")
                    // Fall back to stale cache on network error
                    if let staleCache = SharedRouteCacheService.load() {
                        DispatchQueue.main.async {
                            self.nearbyRoutes = staleCache.routes
                        }
                    }
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

                // Save to cache
                let cache = SharedRouteCache(
                    routes: routes,
                    cachedAt: Date(),
                    userLat: userLat,
                    userLon: userLon,
                    radiusMiles: radiusMiles
                )
                SharedRouteCacheService.save(cache)

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
                    AppLogger.routes.error("Error fetching all routes: \(error)")
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
                AppLogger.routes.error("Geocoding error: \(error)")
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
                        AppLogger.routes.error("Error searching routes: \(error)")
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
                AppLogger.routes.error("Error fetching route GPX: \(error)")
                completion(nil)
                return
            }
            let gpxData = snapshot?.data()?["gpxData"] as? String
            completion(gpxData)
        }
    }

    func getRouteRunNum(docID: String, completion: @escaping (Int?) -> Void) {
        db.collection("sharedRoutes").document(docID).getDocument { snapshot, error in
            if let error = error {
                AppLogger.routes.error("Error fetching route run count: \(error)")
                completion(nil)
                return
            }
            let runCount = snapshot?.data()?["runCount"] as? Int
            AppLogger.routes.debug("Run Count for \(docID): \(runCount ?? 0)")
            completion(runCount)
        }
    }
}
