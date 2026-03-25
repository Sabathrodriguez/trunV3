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

    // Snapshot metadata
    let savedAt: Double            // timeIntervalSince1970
}

enum RunPersistenceService {

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("active_run_snapshot.json")
    }

    static func save(_ snapshot: RunSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[RunPersistence] Failed to save snapshot: \(error)")
        }
    }

    static func load() -> RunSnapshot? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode(RunSnapshot.self, from: data)
        } catch {
            print("[RunPersistence] Failed to load snapshot: \(error)")
            return nil
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    static func hasActiveRun() -> Bool {
        FileManager.default.fileExists(atPath: storageURL.path)
    }
}
