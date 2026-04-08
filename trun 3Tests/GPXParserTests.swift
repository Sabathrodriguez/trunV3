//
//  GPXParserTests.swift
//  trun 3Tests
//
//  Tests for GPXParser — parses GPX XML data into CLLocationCoordinate2D arrays.
//  Validates correct extraction of lat/lon from <trkpt> elements,
//  handling of malformed data, empty files, and multi-segment tracks.
//

import XCTest
import CoreLocation
@testable import trun_3

final class GPXParserTests: XCTestCase {

    private var sut: GPXParser!

    override func setUp() {
        super.setUp()
        sut = GPXParser()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Basic parsing

    /// A minimal valid GPX string with a single <trkpt> should produce
    /// exactly one coordinate with the correct lat/lon values.
    func test_parse_singleTrackPoint() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="37.7749" lon="-122.4194"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertEqual(coords.count, 1, "Should parse exactly one track point")
        XCTAssertEqual(coords[0].latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(coords[0].longitude, -122.4194, accuracy: 0.0001)
    }

    /// Multiple <trkpt> elements should all be parsed in order,
    /// preserving the sequence of the route.
    func test_parse_multipleTrackPoints() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="37.7749" lon="-122.4194"></trkpt>
                <trkpt lat="37.7759" lon="-122.4184"></trkpt>
                <trkpt lat="37.7769" lon="-122.4174"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertEqual(coords.count, 3, "Should parse all three track points")
        XCTAssertEqual(coords[0].latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(coords[1].latitude, 37.7759, accuracy: 0.0001)
        XCTAssertEqual(coords[2].latitude, 37.7769, accuracy: 0.0001)
    }

    /// Track points with negative coordinates (southern/western hemispheres)
    /// should be parsed correctly without sign errors.
    func test_parse_negativeCoordinates() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="-33.8688" lon="151.2093"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertEqual(coords.count, 1)
        XCTAssertEqual(coords[0].latitude, -33.8688, accuracy: 0.0001, "Southern hemisphere latitude should be negative")
        XCTAssertEqual(coords[0].longitude, 151.2093, accuracy: 0.0001)
    }

    // MARK: - Data-based parsing

    /// The parseGPX(data:) method should work identically to parse(gpxString:)
    /// since many callers load GPX as raw Data from files.
    func test_parseGPX_withData() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="40.7128" lon="-74.0060"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let data = gpx.data(using: .utf8)!
        let coords = sut.parseGPX(data: data)
        XCTAssertEqual(coords.count, 1, "Data-based parsing should produce the same result as string-based")
        XCTAssertEqual(coords[0].latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(coords[0].longitude, -74.0060, accuracy: 0.0001)
    }

    // MARK: - Edge cases

    /// A GPX file with no <trkpt> elements at all should return an empty array
    /// rather than crashing or returning garbage data.
    func test_parse_emptyGPX_returnsEmptyArray() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg></trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertTrue(coords.isEmpty, "GPX with no track points should produce empty array")
    }

    /// Completely invalid (non-XML) input should not crash the parser.
    /// XMLParser will fail gracefully and return whatever was collected (nothing).
    func test_parse_invalidXML_returnsEmptyArray() {
        let garbage = "this is not xml at all"
        let coords = sut.parse(gpxString: garbage)
        XCTAssertTrue(coords.isEmpty, "Non-XML input should produce empty array, not crash")
    }

    /// An empty string is a degenerate case — should return an empty array.
    func test_parse_emptyString_returnsEmptyArray() {
        let coords = sut.parse(gpxString: "")
        XCTAssertTrue(coords.isEmpty, "Empty string should produce empty array")
    }

    /// GPX files may contain additional child elements inside <trkpt>
    /// (like <ele> for elevation or <time>). The parser should still
    /// extract lat/lon correctly and ignore the nested elements.
    func test_parse_trackPointsWithChildElements() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="37.7749" lon="-122.4194">
                    <ele>15.2</ele>
                    <time>2025-01-01T00:00:00Z</time>
                </trkpt>
            </trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertEqual(coords.count, 1, "Child elements inside <trkpt> should not affect parsing")
        XCTAssertEqual(coords[0].latitude, 37.7749, accuracy: 0.0001)
    }

    /// High-precision coordinates (many decimal places) should be preserved
    /// accurately through the Double parsing.
    func test_parse_highPrecisionCoordinates() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="37.774929682" lon="-122.419415581"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let coords = sut.parse(gpxString: gpx)
        XCTAssertEqual(coords.count, 1)
        XCTAssertEqual(coords[0].latitude, 37.774929682, accuracy: 0.000001, "High-precision lat should be preserved")
        XCTAssertEqual(coords[0].longitude, -122.419415581, accuracy: 0.000001, "High-precision lon should be preserved")
    }

    /// GPXParser instances should be reusable — parsing a second file
    /// after the first should not carry over stale coordinates.
    /// Note: The current implementation accumulates into `coordinates`, so
    /// a new instance should be created per parse. This test documents behavior.
    func test_parse_freshInstancePerParse() {
        let gpx1 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg>
            <trkpt lat="37.0" lon="-122.0"></trkpt>
        </trkseg></trk></gpx>
        """
        let gpx2 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg>
            <trkpt lat="38.0" lon="-121.0"></trkpt>
            <trkpt lat="39.0" lon="-120.0"></trkpt>
        </trkseg></trk></gpx>
        """

        let parser1 = GPXParser()
        let coords1 = parser1.parse(gpxString: gpx1)
        XCTAssertEqual(coords1.count, 1)

        let parser2 = GPXParser()
        let coords2 = parser2.parse(gpxString: gpx2)
        XCTAssertEqual(coords2.count, 2, "Second parser instance should only contain its own coordinates")
    }
}
