import Foundation
import SwiftUI
import CoreLocation
import HealthKit
import ActivityKit

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

    // Live Activity
    private var currentActivity: Activity<RunActivityAttributes>?

    // MARK: - Live Activity

    func startLiveActivity(activityType: HKWorkoutActivityType, isRouteRun: Bool) {
        let authInfo = ActivityAuthorizationInfo()
        print("[RunSessionManager] Live Activities enabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("[RunSessionManager] Live Activities not enabled — check Settings → trun 3 → Live Activities")
            return
        }

        let attributes = RunActivityAttributes(
            activityType: activityType.name,
            isRouteRun: isRouteRun
        )
        let initialState = RunActivityAttributes.ContentState(
            distanceMiles: 0,
            pace: activityType == .cycling ? "0.0" : "0:00",
            elapsedSeconds: 0,
            isPaused: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            currentActivity = activity
            print("[RunSessionManager] Live Activity started successfully, id: \(activity.id)")
        } catch {
            print("[RunSessionManager] Failed to start Live Activity: \(error)")
        }
    }

    func updateLiveActivity(distanceMiles: Double, pace: String, elapsedSeconds: Double, isPaused: Bool) {
        guard let activity = currentActivity else { return }

        let updatedState = RunActivityAttributes.ContentState(
            distanceMiles: distanceMiles,
            pace: pace,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
    }

    func endLiveActivity() {
        guard let activity = currentActivity else { return }

        let finalState = RunActivityAttributes.ContentState(
            distanceMiles: prevRunDistance,
            pace: prevRunMinPerMile,
            elapsedSeconds: currentTimer,
            isPaused: false
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
        }
        currentActivity = nil
    }

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
