//
//  GoogleRoutesServiceTests.swift
//  trun 3Tests
//
//  Tests for GoogleRoutesService — specifically the polyline decoding algorithm.
//  The decodePolyline method implements Google's Encoded Polyline Algorithm:
//  https://developers.google.com/maps/documentation/utilities/polylinealgorithm
//
//  Network-dependent methods (getRoute, getCyclingRoute) are not tested here
//  because they require a valid API key and network access. The polyline decoder
//  is the core pure-logic piece that can be thoroughly unit tested.
//

import XCTest
import CoreLocation
@testable import trun_3

final class GoogleRoutesServiceTests: XCTestCase {

    private var sut: GoogleRoutesService!

    override func setUp() {
        super.setUp()
        sut = GoogleRoutesService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - decodePolyline

    /// An empty string should decode to an empty coordinate array,
    /// not crash or produce garbage coordinates.
    func test_decodePolyline_emptyString_returnsEmptyArray() {
        let coords = sut.decodePolyline("")
        XCTAssertTrue(coords.isEmpty, "Empty encoded string should produce no coordinates")
    }

    /// The well-known Google example: the encoded polyline "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    /// decodes to three specific coordinates. This is the canonical test case from Google's docs.
    /// Expected: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
    func test_decodePolyline_googleDocExample() {
        let encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let coords = sut.decodePolyline(encoded)

        XCTAssertEqual(coords.count, 3, "Google's example polyline encodes exactly 3 points")
        XCTAssertEqual(coords[0].latitude, 38.5, accuracy: 0.01)
        XCTAssertEqual(coords[0].longitude, -120.2, accuracy: 0.01)
        XCTAssertEqual(coords[1].latitude, 40.7, accuracy: 0.01)
        XCTAssertEqual(coords[1].longitude, -120.95, accuracy: 0.01)
        XCTAssertEqual(coords[2].latitude, 43.252, accuracy: 0.01)
        XCTAssertEqual(coords[2].longitude, -126.453, accuracy: 0.01)
    }

    /// A single encoded coordinate pair should decode to exactly one point.
    /// The encoding "??" represents (0.00000, 0.00000) — the null island.
    func test_decodePolyline_singlePoint_nullIsland() {
        // "??" encodes lat=0, lon=0 (each '?' = ASCII 63, offset by 63 = 0)
        let encoded = "??"
        let coords = sut.decodePolyline(encoded)

        XCTAssertEqual(coords.count, 1, "Should decode exactly one coordinate pair")
        XCTAssertEqual(coords[0].latitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(coords[0].longitude, 0.0, accuracy: 0.00001)
    }

    /// Decoded polyline coordinates should use delta encoding —
    /// each subsequent point is relative to the previous one. Verify
    /// that multi-point polylines correctly accumulate the deltas.
    func test_decodePolyline_deltaEncoding_isAccumulated() {
        // Use the Google example and verify that the second point is NOT
        // just the delta, but the accumulated result.
        let encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let coords = sut.decodePolyline(encoded)

        // The second point should be (40.7, -120.95), not (2.2, -0.75)
        // which would be the raw delta from the first point.
        XCTAssertGreaterThan(coords[1].latitude, 39.0, "Delta should be accumulated, not raw")
    }

    /// Negative coordinate values (southern and western hemispheres)
    /// use the two's complement inversion in the encoding. Verify
    /// that decoding handles the sign bit correctly.
    func test_decodePolyline_negativeValues_decodedCorrectly() {
        let encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let coords = sut.decodePolyline(encoded)

        // All longitudes in this example are negative (western US)
        for coord in coords {
            XCTAssertLessThan(coord.longitude, 0, "Western hemisphere longitudes should be negative")
        }
    }

    // MARK: - RoutesError descriptions

    /// Every RoutesError case must have a non-nil localized description
    /// so the UI can display meaningful error messages to the user.
    func test_routesError_descriptions_areNotNil() {
        let errors: [GoogleRoutesService.RoutesError] = [
            .missingAPIKey,
            .requestFailed("test"),
            .noRouteFound,
            .invalidResponse
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
        }
    }

    /// The missingAPIKey error should mention the plist file name
    /// so the developer knows where to look for the configuration.
    func test_routesError_missingAPIKey_mentionsPlist() {
        let error = GoogleRoutesService.RoutesError.missingAPIKey
        XCTAssertTrue(
            error.errorDescription?.contains("GoogleService-Info.plist") ?? false,
            "Error message should reference the plist file for troubleshooting"
        )
    }
}
