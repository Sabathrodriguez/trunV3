import Foundation
import CoreLocation

class GoogleRoutesService {

    enum RoutesError: LocalizedError {
        case missingAPIKey
        case requestFailed(String)
        case noRouteFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Google Maps API key not found in GoogleService-Info.plist."
            case .requestFailed(let reason):
                return "Google Routes API request failed: \(reason)"
            case .noRouteFound:
                return "No cycling route found between the specified waypoints."
            case .invalidResponse:
                return "Could not parse the Google Routes API response."
            }
        }
    }

    private let endpoint = "https://routes.googleapis.com/directions/v2:computeRoutes"

    private var apiKey: String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["API_KEY"] as? String else {
            return nil
        }
        return key
    }

    /// Get a route through the given waypoints using Google Maps Routes API.
    func getRoute(
        waypoints: [CLLocationCoordinate2D],
        travelMode: String = "WALK"
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distanceMeters: Double) {
        guard waypoints.count >= 2 else {
            throw RoutesError.noRouteFound
        }

        guard let apiKey = apiKey else {
            throw RoutesError.missingAPIKey
        }

        let origin = waypoints.first!
        let destination = waypoints.last!
        let intermediates = Array(waypoints.dropFirst().dropLast())

        let body = buildRequestBody(
            origin: origin,
            destination: destination,
            intermediates: intermediates,
            travelMode: travelMode
        )

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.polyline.encodedPolyline,routes.distanceMeters,routes.legs.polyline.encodedPolyline,routes.legs.distanceMeters",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoutesError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RoutesError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [[String: Any]],
              let firstRoute = routes.first else {
            throw RoutesError.noRouteFound
        }

        // Extract total distance
        let distanceMeters = firstRoute["distanceMeters"] as? Double ?? 0

        // Extract and decode the overall polyline
        guard let polyline = firstRoute["polyline"] as? [String: Any],
              let encodedPolyline = polyline["encodedPolyline"] as? String else {
            throw RoutesError.invalidResponse
        }

        let coordinates = decodePolyline(encodedPolyline)

        guard !coordinates.isEmpty else {
            throw RoutesError.noRouteFound
        }

        return (coordinates, distanceMeters)
    }

    /// Convenience for cycling routes.
    func getCyclingRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distanceMeters: Double) {
        try await getRoute(waypoints: waypoints, travelMode: "BICYCLE")
    }

    /// Convenience for walking routes.
    func getWalkingRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distanceMeters: Double) {
        try await getRoute(waypoints: waypoints, travelMode: "WALK")
    }

    // MARK: - Request Body

    private func buildRequestBody(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        intermediates: [CLLocationCoordinate2D],
        travelMode: String = "BICYCLE"
    ) -> [String: Any] {
        var body: [String: Any] = [
            "origin": locationWaypoint(origin),
            "destination": locationWaypoint(destination),
            "travelMode": travelMode
        ]

        if !intermediates.isEmpty {
            body["intermediates"] = intermediates.map { locationWaypoint($0) }
        }

        return body
    }

    private func locationWaypoint(_ coord: CLLocationCoordinate2D) -> [String: Any] {
        return [
            "location": [
                "latLng": [
                    "latitude": coord.latitude,
                    "longitude": coord.longitude
                ]
            ]
        ]
    }

    // MARK: - Polyline Decoding

    /// Decode a Google encoded polyline string into an array of coordinates.
    /// Reference: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
    func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let characters = Array(encoded.utf8)
        var index = 0
        var latitude: Int32 = 0
        var longitude: Int32 = 0

        while index < characters.count {
            // Decode latitude
            var result: Int32 = 0
            var shift: Int32 = 0
            var byte: Int32

            repeat {
                byte = Int32(characters[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            latitude += deltaLat

            // Decode longitude
            result = 0
            shift = 0

            repeat {
                byte = Int32(characters[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            longitude += deltaLon

            let coord = CLLocationCoordinate2D(
                latitude: Double(latitude) / 1e5,
                longitude: Double(longitude) / 1e5
            )
            coordinates.append(coord)
        }

        return coordinates
    }
}
