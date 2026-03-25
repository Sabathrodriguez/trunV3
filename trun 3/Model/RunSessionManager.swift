import Foundation
import SwiftUI
import CoreLocation
import HealthKit

class RunSessionManager: ObservableObject {
    @Published var runData: Run = Run(time: 0, distance: 0, averagePace: "", caloriesBurned: 0, dateString: "", startTime: Date())
    @Published var currentDate: Date = Date()

    @Published var currentTimer: Double = 0.0
    @Published var isTimerPaused: Bool = false
    @Published var isPaused: Bool = false
    @Published var runStartDate: Date = Date()
    @Published var pausedDuration: Double = 0.0
    @Published var pauseStartDate: Date? = nil

    @Published var isRunDone: Bool = false
    @Published var routeCompleted: Bool = false
    @Published var isSaving: Bool = false

    @Published var prevRunDistance: Double = 0
    @Published var prevRunMinute: Int = 0
    @Published var prevRunSecond: String = ""
    @Published var prevRunMinPerMile: String = "0:00"
    @Published var prevRunElevationGain: Double = 0 // meters

    // Activity type (shared so ContentView can access for scenePhase saves)
    @Published var activityType: HKWorkoutActivityType = .running

    // Captured GPS locations for HealthKit route and Strava export
    var runLocations: [CLLocation] = []

    /// Build a snapshot of the current run state for persistence.
    func buildSnapshot(locationManager: LocationManager) -> RunSnapshot {
        let serializedLocations = locationManager.runLocations.map { SerializableLocation(from: $0) }

        return RunSnapshot(
            runStartDate: runStartDate.timeIntervalSince1970,
            currentTimer: currentTimer,
            pausedDuration: pausedDuration,
            isPaused: isPaused,
            isTimerPaused: isTimerPaused,
            pauseStartDate: pauseStartDate?.timeIntervalSince1970,
            distance: locationManager.distance,
            elevationGain: locationManager.elevationGain,
            locations: serializedLocations,
            activityTypeRawValue: activityType.rawValue,
            savedAt: Date().timeIntervalSince1970
        )
    }
}
