//
//  RouteStorageServiceTests.swift
//  trun 3Tests
//

import XCTest
@testable import trun_3

final class RouteStorageServiceTests: XCTestCase {

    private var tempDir: URL!
    private var sut: RouteStorageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = RouteStorageService(fileManager: .default, directory: tempDir)
    }

    override func tearDownWithError() throws {
        sut = nil
        try FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - loadRoutes

    func test_loadRoutes_returnsNil_whenNoFileExists() {
        XCTAssertNil(sut.loadRoutes())
    }

    func test_saveAndLoad_roundTrip() throws {
        let routes = ["Morning": [makeRoute(name: "Park Loop")]]
        sut.saveRoutes(routes)
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertEqual(loaded["Morning"]?.count, 1)
        XCTAssertEqual(loaded["Morning"]?.first?.name, "Park Loop")
    }

    func test_saveAndLoad_preservesMultipleCategories() throws {
        let routes = [
            "Morning": [makeRoute(name: "Loop A"), makeRoute(name: "Loop B")],
            "Evening": [makeRoute(name: "Riverfront")]
        ]
        sut.saveRoutes(routes)
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertEqual(loaded["Morning"]?.count, 2)
        XCTAssertEqual(loaded["Evening"]?.count, 1)
        XCTAssertEqual(loaded["Evening"]?.first?.name, "Riverfront")
    }

    func test_save_overwritesPreviousData() throws {
        sut.saveRoutes(["Morning": [makeRoute(name: "Old Route")]])
        sut.saveRoutes(["Morning": [makeRoute(name: "New Route")]])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertEqual(loaded["Morning"]?.first?.name, "New Route")
    }

    func test_saveAndLoad_preservesRouteID() throws {
        let route = makeRoute(id: 12345.6, name: "Test")
        sut.saveRoutes(["All": [route]])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        let firstRoute = try XCTUnwrap(loaded["All"]?.first)
        let id = firstRoute.id
        XCTAssertEqual(id, 12345.6, accuracy: 0.001)
    }

    func test_saveAndLoad_preservesColor() throws {
        let route = makeRoute(color: [0.1, 0.5, 0.9, 1.0])
        sut.saveRoutes(["All": [route]])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        let color = try XCTUnwrap(loaded["All"]?.first?.color)
        XCTAssertEqual(color.count, 4)
        XCTAssertEqual(color[0], 0.1, accuracy: 0.001)
    }

    func test_saveAndLoad_preservesSharedRouteID() throws {
        let route = makeRoute(sharedRouteID: "abc-123")
        sut.saveRoutes(["All": [route]])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertEqual(loaded["All"]?.first?.sharedRouteID, "abc-123")
    }

    func test_saveAndLoad_nilSharedRouteID_remainsNil() throws {
        let route = makeRoute(sharedRouteID: nil)
        sut.saveRoutes(["All": [route]])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertNil(loaded["All"]?.first?.sharedRouteID)
    }

    func test_saveEmptyDictionary_loadsAsEmpty() throws {
        sut.saveRoutes([:])
        let loaded = try XCTUnwrap(sut.loadRoutes())
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Helpers

    private func makeRoute(
        id: Double = Double(Int.random(in: 1...999999)),
        name: String = "Test Route",
        gpxURL: String = "file://test.gpx",
        color: [Double] = [1.0, 0.0, 0.0, 1.0],
        sharedRouteID: String? = nil
    ) -> Route {
        Route(id: id, name: name, GPXFileURL: gpxURL, color: color, sharedRouteID: sharedRouteID)
    }
}

