//
//  RunPersistenceService.swift
//  trun 3
//
//  Persists in-progress run state to disk so interrupted runs can be recovered.
//

import Foundation
import CoreLocation

struct SerializableLocation: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Double          // timeIntervalSince1970
    let horizontalAccuracy: Double

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp.timeIntervalSince1970
        self.horizontalAccuracy = location.horizontalAccuracy
    }

    func toCLLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}

struct RunSnapshot: Codable {
    // Timing
    let runStartDate: Double       // timeIntervalSince1970
    let currentTimer: Double
    let pausedDuration: Double
    let isPaused: Bool
    let isTimerPaused: Bool
    let pauseStartDate: Double?    // timeIntervalSince1970, nil if not paused

    // Metrics
    let distance: Double           // meters (from LocationManager.distance)
    let elevationGain: Double      // meters

    // Locations (for HealthKit route + Strava TCX)
    let locations: [SerializableLocation]

    // Activity type
    let activityTypeRawValue: UInt // HKWorkoutActivityType.rawValue

    // Route (nil if no route was selected)
    var selectedRouteID: Double?

    // Snapshot metadata
    let savedAt: Double            // timeIntervalSince1970
}

// MARK: - Protocol

/// Abstraction over persistence so tests can inject a mock store.
protocol PersistenceStore {
    func save(_ snapshot: RunSnapshot)
    func load() -> RunSnapshot?
    func clear()
    func hasActiveRun() -> Bool
}

// MARK: - Concrete Implementation

final class RunPersistenceService: PersistenceStore {

    /// Production shared instance.
    static let shared = RunPersistenceService()

    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        let base = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.storageURL = base.appendingPathComponent("active_run_snapshot.json")
    }

    func save(_ snapshot: RunSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to save run snapshot: \(error)")
        }
    }

    func load() -> RunSnapshot? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode(RunSnapshot.self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to load run snapshot: \(error)")
            return nil
        }
    }

    func clear() {
        try? fileManager.removeItem(at: storageURL)
    }

    func hasActiveRun() -> Bool {
        fileManager.fileExists(atPath: storageURL.path)
    }

    // MARK: - Static Convenience (delegates to shared instance)
    // These allow existing call sites to remain unchanged while tests use DI.

    static func save(_ snapshot: RunSnapshot) { shared.save(snapshot) }
    static func load() -> RunSnapshot? { shared.load() }
    static func clear() { shared.clear() }
    static func hasActiveRun() -> Bool { shared.hasActiveRun() }
}
