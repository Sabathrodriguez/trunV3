import Foundation
import CoreLocation

struct GPXValidator {

    enum ValidationError: LocalizedError {
        case invalidFileExtension
        case fileTooLarge(sizeMB: Double)
        case invalidGPXStructure
        case suspiciousContent
        case invalidCoordinates
        case tooManyPoints(count: Int)
        case routeTooLong(distanceMiles: Double)
        case emptyRoute

        var errorDescription: String? {
            switch self {
            case .invalidFileExtension:
                return "Only .gpx files are supported."
            case .fileTooLarge(let sizeMB):
                return String(format: "File is too large (%.1f MB). Maximum allowed is 5 MB.", sizeMB)
            case .invalidGPXStructure:
                return "The file does not appear to be a valid GPX file."
            case .suspiciousContent:
                return "The file contains disallowed content and cannot be imported."
            case .invalidCoordinates:
                return "The file contains invalid GPS coordinates."
            case .tooManyPoints(let count):
                return "The route has too many points (\(count)). Maximum allowed is 50,000."
            case .routeTooLong(let distanceMiles):
                return String(format: "The route is too long (%.1f miles). Maximum allowed is 50 miles.", distanceMiles)
            case .emptyRoute:
                return "The GPX file contains no track points."
            }
        }
    }

    static let maxFileSizeBytes: Int = 5 * 1024 * 1024 // 5 MB
    static let maxCoordinateCount: Int = 50_000
    static let maxDistanceMiles: Double = 50.0
    static let maxRouteNameLength: Int = 100

    // MARK: - File-level validation

    /// Validates a GPX file URL before reading its contents.
    static func validateFile(at url: URL) throws {
        // 1. Check file extension
        guard url.pathExtension.lowercased() == "gpx" else {
            throw ValidationError.invalidFileExtension
        }

        // 2. Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attributes[.size] as? Int, fileSize > maxFileSizeBytes {
            let sizeMB = Double(fileSize) / (1024.0 * 1024.0)
            throw ValidationError.fileTooLarge(sizeMB: sizeMB)
        }
    }

    // MARK: - Content validation

    /// Validates the raw GPX string content for structure and suspicious patterns.
    static func validateContent(_ gpxString: String) throws {
        let lowered = gpxString.lowercased()

        // Check for GPX root element
        guard lowered.contains("<gpx") else {
            throw ValidationError.invalidGPXStructure
        }

        // Check for track points
        guard lowered.contains("<trkpt") else {
            throw ValidationError.emptyRoute
        }

        // Reject suspicious/malicious content
        let suspiciousPatterns = [
            "<script", "javascript:", "onclick", "onerror", "onload",
            "<!entity", "<!doctype", "system \"", "public \""
        ]
        for pattern in suspiciousPatterns {
            if lowered.contains(pattern) {
                throw ValidationError.suspiciousContent
            }
        }
    }

    // MARK: - Coordinate validation

    /// Validates parsed coordinates for range, count, and total distance.
    static func validateCoordinates(_ coords: [CLLocationCoordinate2D]) throws {
        guard !coords.isEmpty else {
            throw ValidationError.emptyRoute
        }

        // Check count
        if coords.count > maxCoordinateCount {
            throw ValidationError.tooManyPoints(count: coords.count)
        }

        // Check coordinate ranges
        for coord in coords {
            if coord.latitude < -90 || coord.latitude > 90 ||
               coord.longitude < -180 || coord.longitude > 180 {
                throw ValidationError.invalidCoordinates
            }
        }

        // Check total distance
        let distanceMiles = calculateDistanceMiles(coords)
        if distanceMiles > maxDistanceMiles {
            throw ValidationError.routeTooLong(distanceMiles: distanceMiles)
        }
    }

    // MARK: - Name sanitization

    /// Sanitizes a route name by stripping HTML tags and limiting length.
    static func sanitizeRouteName(_ name: String) -> String {
        // Strip HTML tags
        let stripped = name.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Trim whitespace
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length
        if trimmed.count > maxRouteNameLength {
            return String(trimmed.prefix(maxRouteNameLength))
        }

        return trimmed
    }

    // MARK: - Helpers

    static func calculateDistanceMiles(_ coords: [CLLocationCoordinate2D]) -> Double {
        var totalMeters: Double = 0
        for i in 1..<coords.count {
            let prev = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
            let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            totalMeters += curr.distance(from: prev)
        }
        return totalMeters * 0.000621371
    }
}
