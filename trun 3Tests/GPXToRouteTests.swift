//
//  GPXToRouteTests.swift
//  trun 3Tests
//
//  Tests for GPXToRoute — reads GPX files from the filesystem (absolute path,
//  Documents directory, or app bundle) and converts them into coordinate arrays.
//  Uses temporary files to simulate imported GPX data on disk.
//

import XCTest
import CoreLocation
@testable import trun_3

final class GPXToRouteTests: XCTestCase {

    private var sut: GPXToRoute!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = GPXToRoute()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        sut = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a temporary GPX file with the given track points and returns its path.
    private func createTempGPXFile(name: String = "test.gpx", trackPoints: String) -> String {
        let gpxContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TestSuite">
            <trk>
                <name>\(name)</name>
                <trkseg>
                    \(trackPoints)
                </trkseg>
            </trk>
        </gpx>
        """
        let fileURL = tempDir.appendingPathComponent(name)
        try? gpxContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    // MARK: - readGPXFile (absolute path)

    /// When given a valid absolute file path to a GPX file on disk,
    /// readGPXFile should parse it and return the correct coordinates.
    func test_readGPXFile_validAbsolutePath_returnsCoordinates() {
        let path = createTempGPXFile(trackPoints: """
            <trkpt lat="37.7749" lon="-122.4194"></trkpt>
            <trkpt lat="37.7759" lon="-122.4184"></trkpt>
        """)

        let coords = sut.readGPXFile(fileName: path)
        XCTAssertNotNil(coords, "Should successfully parse GPX from absolute path")
        XCTAssertEqual(coords?.count, 2, "Should find both track points")
        XCTAssertEqual(coords?[0].latitude ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(coords?[1].longitude ?? 0, -122.4184, accuracy: 0.0001)
    }

    /// If the file path doesn't exist and the filename isn't in Documents
    /// or the app bundle, readGPXFile should return nil without crashing.
    func test_readGPXFile_nonexistentPath_returnsNil() {
        let coords = sut.readGPXFile(fileName: "/nonexistent/path/route.gpx")
        XCTAssertNil(coords, "Non-existent file should return nil, not crash")
    }

    /// An empty GPX file (valid XML but no track points) should return
    /// an empty coordinate array, not nil.
    func test_readGPXFile_emptyGPX_returnsEmptyArray() {
        let path = createTempGPXFile(
            name: "empty.gpx",
            trackPoints: ""
        )
        let coords = sut.readGPXFile(fileName: path)
        // Parser will return empty array since no <trkpt> elements exist
        XCTAssertNotNil(coords, "Valid file with no points should return empty array, not nil")
        XCTAssertEqual(coords?.count, 0)
    }

    // MARK: - convertGPXToRoute

    /// convertGPXToRoute is a convenience wrapper around readGPXFile.
    /// It should return the same coordinates for a valid file.
    func test_convertGPXToRoute_validFile_returnsCoordinates() {
        let path = createTempGPXFile(trackPoints: """
            <trkpt lat="40.7128" lon="-74.0060"></trkpt>
        """)

        let coords = sut.convertGPXToRoute(filePath: path)
        XCTAssertNotNil(coords, "convertGPXToRoute should delegate to readGPXFile successfully")
        XCTAssertEqual(coords?.count, 1)
        XCTAssertEqual(coords?[0].latitude ?? 0, 40.7128, accuracy: 0.0001)
    }

    /// convertGPXToRoute should return nil when the underlying file doesn't exist,
    /// matching readGPXFile's behavior.
    func test_convertGPXToRoute_invalidPath_returnsNil() {
        let coords = sut.convertGPXToRoute(filePath: "/does/not/exist.gpx")
        XCTAssertNil(coords, "Invalid path should propagate nil from readGPXFile")
    }

    // MARK: - Multiple track points with various data

    /// A GPX file with many track points should be fully parsed,
    /// verifying that the parser handles realistic route sizes.
    func test_readGPXFile_manyTrackPoints() {
        var points = ""
        for i in 0..<100 {
            let lat = 37.7749 + Double(i) * 0.0001
            points += "<trkpt lat=\"\(lat)\" lon=\"-122.4194\"></trkpt>\n"
        }
        let path = createTempGPXFile(name: "long_route.gpx", trackPoints: points)

        let coords = sut.readGPXFile(fileName: path)
        XCTAssertEqual(coords?.count, 100, "All 100 track points should be parsed")
    }
}
