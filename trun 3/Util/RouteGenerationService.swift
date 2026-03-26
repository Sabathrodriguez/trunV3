import Foundation
import MapKit
import CoreLocation

@available(iOS 26.0, *)
struct RouteOption: Identifiable {
    let id = UUID()
    let source: String
    let coordinates: [CLLocationCoordinate2D]
    let gpxString: String
    let distanceMiles: Double
}

@available(iOS 26.0, *)
class RouteGenerationService: ObservableObject {

    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = ""
    @Published var routeOptions: [RouteOption] = []

    private let nlpParser = RouteNLPParser()
    private let waypointGenerator = WaypointGenerator()
    private let googleRoutesService = GoogleRoutesService()
    private let apiBudgetService = APIBudgetService.shared

    enum GenerationError: LocalizedError {
        case noUserLocation
        case directionsUnavailable(String)
        case geocodingFailed
        case noRoutesGenerated

        var errorDescription: String? {
            switch self {
            case .noUserLocation:
                return "Unable to determine your current location."
            case .directionsUnavailable(let reason):
                return "Could not calculate walking directions: \(reason)"
            case .geocodingFailed:
                return "Could not find the specified location."
            case .noRoutesGenerated:
                return "Neither routing service could generate a route. Please try again."
            }
        }
    }

    func generateRoute(
        userInput: String,
        userLocation: CLLocationCoordinate2D,
        activityType: ActivityType? = nil
    ) async throws {

        await MainActor.run {
            isGenerating = true
            generationProgress = "Understanding your request..."
            routeOptions = []
        }

        do {
            var request = try await nlpParser.parseRequest(userInput)

            if let activityType = activityType {
                request.activityType = activityType
            }

            let activityLabel: String
            switch request.activityType {
            case .running: activityLabel = "running"
            case .walking: activityLabel = "walking"
            case .cycling: activityLabel = "cycling"
            }

            await MainActor.run {
                generationProgress = "Planning \(String(format: "%.1f", request.targetDistanceMiles)) mile \(activityLabel) \(request.routeType.rawValue) route..."
            }

            var biasCoordinate: CLLocationCoordinate2D? = nil
            if let dirPref = request.directionPreference, !dirPref.isEmpty {
                biasCoordinate = try? await geocodeDirection(dirPref)
            }

            let waypoints = waypointGenerator.generateWaypoints(
                from: userLocation,
                request: request,
                directionBiasCoordinate: biasCoordinate
            )

            var options: [RouteOption] = []
            let googleEnabled = await apiBudgetService.isGoogleRoutesEnabled()

            if request.activityType == .cycling {
                if googleEnabled {
                    // Cycling: Google Routes (with distance-accuracy loop)
                    await MainActor.run {
                        generationProgress = "Calculating cycling route..."
                    }

                    if let route = await fetchGoogleRoute(
                        waypoints: waypoints,
                        activityType: .cycling,
                        targetDistanceMiles: request.targetDistanceMiles,
                        userLocation: userLocation
                    ) {
                        options.append(route)
                    }
                } else {
                    // Google disabled — fall back to Apple Maps walking as approximation
                    await MainActor.run {
                        generationProgress = "Calculating approximate cycling route..."
                    }

                    if let route = await fetchAppleMapsRoute(
                        waypoints: waypoints,
                        request: request,
                        userLocation: userLocation,
                        activityLabel: activityLabel,
                        sourceLabel: "Apple Maps (approx.)"
                    ) {
                        options.append(route)
                    }
                }
            } else {
                if googleEnabled {
                    // Walking/Running: fetch from both APIs in parallel
                    await MainActor.run {
                        generationProgress = "Calculating routes from Apple Maps & Google..."
                    }

                    async let appleResult = fetchAppleMapsRoute(
                        waypoints: waypoints,
                        request: request,
                        userLocation: userLocation,
                        activityLabel: activityLabel
                    )

                    async let googleResult = fetchGoogleRoute(
                        waypoints: waypoints,
                        activityType: request.activityType,
                        targetDistanceMiles: request.targetDistanceMiles,
                        userLocation: userLocation
                    )

                    let apple = await appleResult
                    let google = await googleResult

                    if let apple = apple {
                        options.append(apple)
                    }
                    if let google = google {
                        options.append(google)
                    }
                } else {
                    // Google disabled — Apple Maps only
                    await MainActor.run {
                        generationProgress = "Calculating route from Apple Maps..."
                    }

                    if let route = await fetchAppleMapsRoute(
                        waypoints: waypoints,
                        request: request,
                        userLocation: userLocation,
                        activityLabel: activityLabel
                    ) {
                        options.append(route)
                    }
                }
            }

            guard !options.isEmpty else {
                throw GenerationError.noRoutesGenerated
            }

            await MainActor.run {
                routeOptions = options
                isGenerating = false
                generationProgress = "Done!"
            }

        } catch {
            await MainActor.run {
                isGenerating = false
                generationProgress = ""
            }
            throw error
        }
    }

    // MARK: - Apple Maps Route (with distance-accuracy loop)

    private func fetchAppleMapsRoute(
        waypoints: [CLLocationCoordinate2D],
        request: RouteRequest,
        userLocation: CLLocationCoordinate2D,
        activityLabel: String,
        sourceLabel: String = "Apple Maps"
    ) async -> RouteOption? {
        do {
            var currentWaypoints = waypoints
            let maxIterations = 3
            let tolerance = 0.15
            var finalCoordinates: [CLLocationCoordinate2D] = []
            var finalDistance: Double = 0

            for iteration in 0..<maxIterations {
                let routeResult = try await assembleWalkingRoute(waypoints: currentWaypoints)
                finalCoordinates = routeResult.coordinates
                finalDistance = routeResult.distanceMiles

                let ratio = finalDistance / request.targetDistanceMiles
                if abs(ratio - 1.0) <= tolerance {
                    break
                }

                if iteration < maxIterations - 1 {
                    let scaleFactor = request.targetDistanceMiles / finalDistance
                    currentWaypoints = waypointGenerator.adjustWaypoints(
                        currentWaypoints,
                        around: userLocation,
                        scaleFactor: scaleFactor
                    )
                }
            }

            let gpx = createGPXString(from: finalCoordinates)
            try GPXValidator.validateCoordinates(finalCoordinates)

            return RouteOption(
                source: sourceLabel,
                coordinates: finalCoordinates,
                gpxString: gpx,
                distanceMiles: finalDistance
            )
        } catch {
            print("Apple Maps route failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Google Routes

    private func fetchGoogleRoute(
        waypoints: [CLLocationCoordinate2D],
        activityType: ActivityType,
        targetDistanceMiles: Double,
        userLocation: CLLocationCoordinate2D
    ) async -> RouteOption? {
        do {
            var currentWaypoints = waypoints
            let maxIterations = 3
            let tolerance = 0.15
            var finalCoordinates: [CLLocationCoordinate2D] = []
            var finalDistance: Double = 0

            for iteration in 0..<maxIterations {
                let result: (coordinates: [CLLocationCoordinate2D], distanceMeters: Double)
                if activityType == .cycling {
                    result = try await googleRoutesService.getCyclingRoute(waypoints: currentWaypoints)
                } else {
                    result = try await googleRoutesService.getWalkingRoute(waypoints: currentWaypoints)
                }

                finalCoordinates = result.coordinates
                finalDistance = result.distanceMeters * 0.000621371

                let ratio = finalDistance / targetDistanceMiles
                if abs(ratio - 1.0) <= tolerance {
                    break
                }

                if iteration < maxIterations - 1 {
                    let scaleFactor = targetDistanceMiles / finalDistance
                    currentWaypoints = waypointGenerator.adjustWaypoints(
                        currentWaypoints,
                        around: userLocation,
                        scaleFactor: scaleFactor
                    )
                }
            }

            let gpx = createGPXString(from: finalCoordinates)
            try GPXValidator.validateCoordinates(finalCoordinates)

            return RouteOption(
                source: "Google Routes",
                coordinates: finalCoordinates,
                gpxString: gpx,
                distanceMiles: finalDistance
            )
        } catch {
            print("Google Routes failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - MKDirections Assembly

    private func assembleWalkingRoute(
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
