import Foundation
import SwiftUI
import CoreLocation
import HealthKit
import ActivityKit

// MARK: - Run State Machine

/// Explicit lifecycle states for a run session.
/// Use this instead of multiple overlapping boolean flags.
enum RunState: Equatable {
    case idle
    case running
    case paused
    case completed
}

// MARK: - RunSessionManager

class RunSessionManager: ObservableObject {
    @Published var runData: Run = Run(time: 0, distance: 0, averagePace: "", caloriesBurned: 0, dateString: "", startTime: Date())
    @Published var currentDate: Date = Date()

    @Published var currentTimer: Double = 0.0
    @Published var runStartDate: Date = Date()
    @Published var pausedDuration: Double = 0.0
    @Published var pauseStartDate: Date? = nil

    // MARK: Run State (single source of truth)
    @Published var runState: RunState = .idle

    /// Backward-compatible computed properties so existing view code needs no changes.
    var isPaused: Bool {
        get { runState == .paused }
        set { runState = newValue ? .paused : .running }
    }
    var isTimerPaused: Bool {
        get { runState == .paused }
        set { runState = newValue ? .paused : .running }
    }
    var isRunDone: Bool {
        get { runState == .completed }
        set { runState = newValue ? .completed : .idle }
    }

    @Published var routeCompleted: Bool = false
    @Published var isSaving: Bool = false

    @Published var prevRunDistance: Double = 0
    @Published var prevRunMinute: Int = 0
    @Published var prevRunSecond: String = ""
    @Published var prevRunMinPerMile: String = "0:00"
    @Published var prevRunElevationGain: Double = 0 // meters

    // Activity type (shared so ContentView can access for scenePhase saves)
    @Published var activityType: HKWorkoutActivityType = .running

    // Published Live Activity error so views can surface failures
    @Published var liveActivityError: Error?

    // Captured GPS locations for HealthKit route and Strava export
    var runLocations: [CLLocation] = []

    // MARK: - Dependencies (injectable for testing)

    private let liveActivityService: LiveActivityManaging

    init(liveActivityService: LiveActivityManaging = DefaultLiveActivityService()) {
        self.liveActivityService = liveActivityService
    }

    // MARK: - Live Activity

    func startLiveActivity(activityType: HKWorkoutActivityType, isRouteRun: Bool) {
        let authInfo = ActivityAuthorizationInfo()
        AppLogger.liveActivity.debug("Live Activities enabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            AppLogger.liveActivity.error("Live Activities not enabled — check Settings → trun 3 → Live Activities")
            return
        }

        let initialPace = activityType == .cycling ? "0.0" : "0:00"

        do {
            try liveActivityService.start(
                activityType: activityType.name,
                isRouteRun: isRouteRun,
                pace: initialPace
            )
        } catch {
            AppLogger.liveActivity.error("Failed to start Live Activity: \(error)")
            DispatchQueue.main.async { self.liveActivityError = error }
        }
    }

    func updateLiveActivity(distanceMiles: Double, pace: String, elapsedSeconds: Double, isPaused: Bool) {
        Task {
            await liveActivityService.update(
                distanceMiles: distanceMiles,
                pace: pace,
                elapsedSeconds: elapsedSeconds,
                isPaused: isPaused
            )
        }
    }

    func endLiveActivity() {
        liveActivityService.end(
            distanceMiles: prevRunDistance,
            pace: prevRunMinPerMile,
            elapsedSeconds: currentTimer
        )
    }

    /// Build a snapshot of the current run state for persistence.
    func buildSnapshot(locationManager: LocationManager, selectedRouteID: Double? = nil) -> RunSnapshot {
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
            selectedRouteID: selectedRouteID,
            savedAt: Date().timeIntervalSince1970
        )
    }
}
