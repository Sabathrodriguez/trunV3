//
//  GPXValidatorTests.swift
//  trun 3Tests
//
//  Tests for GPXValidator — validates GPX file extension, size, content structure,
//  coordinate ranges, route distance limits, and name sanitization.
//

import XCTest
import CoreLocation
@testable import trun_3

final class GPXValidatorTests: XCTestCase {

    // MARK: - validateFile (file-level checks)

    /// A non-.gpx extension (e.g. .txt) should be rejected immediately,
    /// preventing the app from attempting to parse non-GPX data.
    func test_validateFile_throwsInvalidFileExtension_forNonGPX() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try GPXValidator.validateFile(at: url)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .invalidFileExtension = validationError {} else {
                XCTFail("Expected invalidFileExtension, got \(validationError)")
            }
        }
    }

    /// Files exceeding the 5 MB limit should be rejected to prevent
    /// excessive memory usage during XML parsing.
    func test_validateFile_throwsFileTooLarge_forOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("big.gpx")
        let data = Data(count: GPXValidator.maxFileSizeBytes + 1)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try GPXValidator.validateFile(at: url)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .fileTooLarge = validationError {} else {
                XCTFail("Expected fileTooLarge, got \(validationError)")
            }
        }
    }

    /// A small, correctly-named .gpx file should pass file-level validation
    /// (content is checked separately by validateContent).
    func test_validateFile_succeeds_forValidSmallGPXFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("valid.gpx")
        let data = Data("test".utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(try GPXValidator.validateFile(at: url))
    }

    // MARK: - validateContent (structure & security checks)

    /// XML without a <gpx> root element is not a valid GPX file.
    /// The validator should reject it before attempting further parsing.
    func test_validateContent_throwsInvalidGPXStructure_withoutGPXTag() {
        let content = "<xml><data>hello</data></xml>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .invalidGPXStructure = validationError {} else {
                XCTFail("Expected invalidGPXStructure, got \(validationError)")
            }
        }
    }

    /// A GPX file with a valid root element but no <trkpt> track points
    /// contains no usable route data and should be rejected.
    func test_validateContent_throwsEmptyRoute_withoutTrackPoints() {
        let content = "<gpx><metadata></metadata></gpx>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .emptyRoute = validationError {} else {
                XCTFail("Expected emptyRoute, got \(validationError)")
            }
        }
    }

    /// <script> tags embedded in a GPX file indicate a potential XSS attack.
    /// The validator rejects any file containing suspicious HTML/JS content.
    func test_validateContent_throwsSuspiciousContent_withScript() {
        let content = "<gpx><trkpt><script>alert('xss')</script></trkpt></gpx>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .suspiciousContent = validationError {} else {
                XCTFail("Expected suspiciousContent, got \(validationError)")
            }
        }
    }

    /// "javascript:" URIs are a classic XSS vector. Even inside GPX data,
    /// their presence signals a malicious or corrupted file.
    func test_validateContent_throwsSuspiciousContent_withJavascript() {
        let content = "<gpx><trkpt>javascript:void(0)</trkpt></gpx>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .suspiciousContent = validationError {} else {
                XCTFail("Expected suspiciousContent, got \(validationError)")
            }
        }
    }

    /// Inline event handlers like onclick are HTML injection vectors.
    /// GPX files should never contain them.
    func test_validateContent_throwsSuspiciousContent_withOnClick() {
        let content = "<gpx><trkpt onclick='bad()'>data</trkpt></gpx>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .suspiciousContent = validationError {} else {
                XCTFail("Expected suspiciousContent, got \(validationError)")
            }
        }
    }

    /// XML External Entity (XXE) injection via <!ENTITY allows attackers
    /// to read local files or trigger SSRF. The validator blocks this pattern.
    func test_validateContent_throwsSuspiciousContent_withEntityInjection() {
        let content = "<gpx><!ENTITY xxe SYSTEM 'file:///etc/passwd'><trkpt lat='0' lon='0'></trkpt></gpx>"
        XCTAssertThrowsError(try GPXValidator.validateContent(content)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .suspiciousContent = validationError {} else {
                XCTFail("Expected suspiciousContent, got \(validationError)")
            }
        }
    }

    /// A well-formed GPX string with a <gpx> root and at least one <trkpt>
    /// should pass content validation successfully.
    func test_validateContent_succeeds_forValidGPX() {
        let content = """
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="37.7749" lon="-122.4194"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        XCTAssertNoThrow(try GPXValidator.validateContent(content))
    }

    // MARK: - validateCoordinates (parsed coordinate checks)

    /// An empty coordinate array means the GPX was parsed but yielded no points.
    /// This is treated as an empty route.
    func test_validateCoordinates_throwsEmptyRoute_forEmptyArray() {
        XCTAssertThrowsError(try GPXValidator.validateCoordinates([])) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .emptyRoute = validationError {} else {
                XCTFail("Expected emptyRoute, got \(validationError)")
            }
        }
    }

    /// Routes with more than 50,000 track points are rejected to prevent
    /// performance issues when rendering on the map or processing in memory.
    func test_validateCoordinates_throwsTooManyPoints_overLimit() {
        let coords = (0...GPXValidator.maxCoordinateCount).map { i in
            CLLocationCoordinate2D(latitude: 37.0 + Double(i) * 0.00001, longitude: -122.0)
        }
        XCTAssertThrowsError(try GPXValidator.validateCoordinates(coords)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .tooManyPoints = validationError {} else {
                XCTFail("Expected tooManyPoints, got \(validationError)")
            }
        }
    }

    /// Latitude values above 90 degrees are physically impossible on Earth.
    /// The validator catches corrupted or fabricated coordinate data.
    func test_validateCoordinates_throwsInvalidCoordinates_latitudeOver90() {
        let coords = [CLLocationCoordinate2D(latitude: 91.0, longitude: 0.0)]
        XCTAssertThrowsError(try GPXValidator.validateCoordinates(coords)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .invalidCoordinates = validationError {} else {
                XCTFail("Expected invalidCoordinates, got \(validationError)")
            }
        }
    }

    /// Latitude values below -90 degrees are physically impossible.
    func test_validateCoordinates_throwsInvalidCoordinates_latitudeUnderNeg90() {
        let coords = [CLLocationCoordinate2D(latitude: -91.0, longitude: 0.0)]
        XCTAssertThrowsError(try GPXValidator.validateCoordinates(coords)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .invalidCoordinates = validationError {} else {
                XCTFail("Expected invalidCoordinates, got \(validationError)")
            }
        }
    }

    /// Longitude values above 180 degrees are outside the valid range.
    func test_validateCoordinates_throwsInvalidCoordinates_longitudeOver180() {
        let coords = [CLLocationCoordinate2D(latitude: 0.0, longitude: 181.0)]
        XCTAssertThrowsError(try GPXValidator.validateCoordinates(coords)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .invalidCoordinates = validationError {} else {
                XCTFail("Expected invalidCoordinates, got \(validationError)")
            }
        }
    }

    /// Routes longer than 50 miles are rejected. This test uses two points
    /// separated by 1 degree of latitude (~69 miles) to exceed the limit.
    func test_validateCoordinates_throwsRouteTooLong() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 38.0, longitude: -122.0)
        ]
        XCTAssertThrowsError(try GPXValidator.validateCoordinates(coords)) { error in
            guard let validationError = error as? GPXValidator.ValidationError else {
                return XCTFail("Wrong error type")
            }
            if case .routeTooLong = validationError {} else {
                XCTFail("Expected routeTooLong, got \(validationError)")
            }
        }
    }

    /// A short route with valid coordinates should pass all checks.
    func test_validateCoordinates_succeeds_forValidShortRoute() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7759, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7769, longitude: -122.4194)
        ]
        XCTAssertNoThrow(try GPXValidator.validateCoordinates(coords))
    }

    /// Exact boundary values (lat ±90, lon ±180) are valid coordinates.
    /// The route will be too long (spans the earth), but the coordinates
    /// themselves should not trigger an invalidCoordinates error.
    func test_validateCoordinates_boundaryValues_areValidCoordinates() {
        let coords = [
            CLLocationCoordinate2D(latitude: 90.0, longitude: 180.0),
            CLLocationCoordinate2D(latitude: -90.0, longitude: -180.0)
        ]
        do {
            try GPXValidator.validateCoordinates(coords)
            XCTFail("Expected routeTooLong for earth-spanning route")
        } catch let error as GPXValidator.ValidationError {
            if case .invalidCoordinates = error {
                XCTFail("Boundary values (-90/90, -180/180) should be valid coordinates")
            }
            // .routeTooLong is the expected error here
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - sanitizeRouteName

    /// HTML tags like <b> should be stripped so route names display as plain text.
    func test_sanitizeRouteName_stripsHTMLTags() {
        XCTAssertEqual(GPXValidator.sanitizeRouteName("<b>My Route</b>"), "My Route")
    }

    /// Leading and trailing whitespace should be trimmed for clean display.
    func test_sanitizeRouteName_trimsWhitespace() {
        XCTAssertEqual(GPXValidator.sanitizeRouteName("  My Route  "), "My Route")
    }

    /// Names exceeding 100 characters are truncated to prevent UI layout issues
    /// and potential storage overflow.
    func test_sanitizeRouteName_limitsLength() {
        let longName = String(repeating: "A", count: 200)
        let result = GPXValidator.sanitizeRouteName(longName)
        XCTAssertEqual(result.count, GPXValidator.maxRouteNameLength)
    }

    /// An empty string should remain empty after sanitization (no crash).
    func test_sanitizeRouteName_handlesEmptyString() {
        XCTAssertEqual(GPXValidator.sanitizeRouteName(""), "")
    }

    /// Deeply nested HTML tags should all be removed, leaving only the text content.
    func test_sanitizeRouteName_stripsNestedTags() {
        XCTAssertEqual(GPXValidator.sanitizeRouteName("<div><span>Route</span></div>"), "Route")
    }

    /// Plain text without any HTML should pass through unchanged.
    func test_sanitizeRouteName_preservesPlainText() {
        XCTAssertEqual(GPXValidator.sanitizeRouteName("Morning Run"), "Morning Run")
    }

    // MARK: - calculateDistanceMiles

    /// A single point has no distance to measure — should return exactly 0.
    func test_calculateDistanceMiles_returnsZero_forSinglePoint() {
        let coords = [CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)]
        XCTAssertEqual(GPXValidator.calculateDistanceMiles(coords), 0.0, accuracy: 0.001)
    }

    /// Two points ~1.1 km apart should yield approximately 0.69 miles,
    /// verifying the meters-to-miles conversion factor is correct.
    func test_calculateDistanceMiles_returnsCorrectValue_forKnownDistance() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194)
        ]
        let distance = GPXValidator.calculateDistanceMiles(coords)
        XCTAssertGreaterThan(distance, 0)
        XCTAssertEqual(distance, 0.69, accuracy: 0.1)
    }

    // MARK: - ValidationError localized descriptions

    /// Every error case must provide a user-facing description string
    /// so the UI can display meaningful feedback when import fails.
    func test_validationError_descriptions_areNotNil() {
        let errors: [GPXValidator.ValidationError] = [
            .invalidFileExtension,
            .fileTooLarge(sizeMB: 10.0),
            .invalidGPXStructure,
            .suspiciousContent,
            .invalidCoordinates,
            .tooManyPoints(count: 100000),
            .routeTooLong(distanceMiles: 75.0),
            .emptyRoute
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
        }
    }
}
