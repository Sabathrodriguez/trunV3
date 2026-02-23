import Foundation
import MapKit
import CoreLocation

@available(iOS 26.0, *)
class RouteGenerationService: ObservableObject {

    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = ""
    @Published var previewCoordinates: [CLLocationCoordinate2D]?
    @Published var generatedDistanceMiles: Double = 0

    private let nlpParser = RouteNLPParser()
    private let waypointGenerator = WaypointGenerator()

    enum GenerationError: LocalizedError {
        case noUserLocation
        case directionsUnavailable(String)
        case geocodingFailed

        var errorDescription: String? {
            switch self {
            case .noUserLocation:
                return "Unable to determine your current location."
            case .directionsUnavailable(let reason):
                return "Could not calculate walking directions: \(reason)"
            case .geocodingFailed:
                return "Could not find the specified location."
            }
        }
    }

    func generateRoute(
        userInput: String,
        userLocation: CLLocationCoordinate2D
    ) async throws -> (coordinates: [CLLocationCoordinate2D], gpxString: String, distanceMiles: Double) {

        await MainActor.run {
            isGenerating = true
            generationProgress = "Understanding your request..."
        }

        do {
            let request = try await nlpParser.parseRequest(userInput)

            await MainActor.run {
                generationProgress = "Planning \(String(format: "%.1f", request.targetDistanceMiles)) mile \(request.routeType.rawValue) route..."
            }

            var biasCoordinate: CLLocationCoordinate2D? = nil
            if let dirPref = request.directionPreference, !dirPref.isEmpty {
                biasCoordinate = try? await geocodeDirection(dirPref)
            }

            var waypoints = waypointGenerator.generateWaypoints(
                from: userLocation,
                request: request,
                directionBiasCoordinate: biasCoordinate
            )

            let maxIterations = 3
            let tolerance = 0.15
            var finalCoordinates: [CLLocationCoordinate2D] = []
            var finalDistance: Double = 0

            for iteration in 0..<maxIterations {
                await MainActor.run {
                    generationProgress = "Calculating route (attempt \(iteration + 1)/\(maxIterations))..."
                }

                let routeResult = try await assembleRoute(waypoints: waypoints)
                finalCoordinates = routeResult.coordinates
                finalDistance = routeResult.distanceMiles

                let ratio = finalDistance / request.targetDistanceMiles
                if abs(ratio - 1.0) <= tolerance {
                    break
                }

                if iteration < maxIterations - 1 {
                    let scaleFactor = request.targetDistanceMiles / finalDistance
                    waypoints = waypointGenerator.adjustWaypoints(
                        waypoints,
                        around: userLocation,
                        scaleFactor: scaleFactor
                    )
                }
            }

            await MainActor.run {
                generationProgress = "Generating route file..."
                previewCoordinates = finalCoordinates
                generatedDistanceMiles = finalDistance
            }

            let gpxString = createGPXString(from: finalCoordinates)

            try GPXValidator.validateContent(gpxString)
            try GPXValidator.validateCoordinates(finalCoordinates)

            await MainActor.run {
                isGenerating = false
                generationProgress = "Done!"
            }

            return (finalCoordinates, gpxString, finalDistance)

        } catch {
            await MainActor.run {
                isGenerating = false
                generationProgress = ""
            }
            throw error
        }
    }

    // MARK: - MKDirections Assembly

    private func assembleRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distanceMiles: Double) {

        var allCoordinates: [CLLocationCoordinate2D] = []
        var totalDistanceMeters: Double = 0

        for i in 0..<(waypoints.count - 1) {
            let source = MKMapItem(placemark: MKPlacemark(coordinate: waypoints[i]))
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: waypoints[i + 1]))

            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = .walking

            let directions = MKDirections(request: request)

            let response: MKDirections.Response
            do {
                response = try await directions.calculate()
            } catch {
                throw GenerationError.directionsUnavailable(error.localizedDescription)
            }

            guard let route = response.routes.first else {
                throw GenerationError.directionsUnavailable("No walking route found between waypoints.")
            }

            let polyline = route.polyline
            let pointCount = polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

            if !allCoordinates.isEmpty {
                coords.removeFirst()
            }

            allCoordinates.append(contentsOf: coords)
            totalDistanceMeters += route.distance
        }

        let totalMiles = totalDistanceMeters * 0.000621371
        return (allCoordinates, totalMiles)
    }

    // MARK: - Geocoding

    private func geocodeDirection(_ directionText: String) async throws -> CLLocationCoordinate2D {
        let geocoder = CLGeocoder()
        let results = try await geocoder.geocodeAddressString(directionText)

        guard let placemark = results.first, let location = placemark.location else {
            throw GenerationError.geocodingFailed
        }

        return location.coordinate
    }

    // MARK: - GPX Generation

    func createGPXString(from coordinates: [CLLocationCoordinate2D]) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrunApp" xmlns="http://www.topografix.com/GPX/1/1">
            <trk>
                <name>AI Generated Route</name>
                <trkseg>
        """

        for coord in coordinates {
            gpx += "\n            <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"></trkpt>"
        }

        gpx += """

                </trkseg>
            </trk>
        </gpx>
        """

        return gpx
    }
}
