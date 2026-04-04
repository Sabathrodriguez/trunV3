//
//  DefaultLiveActivityService.swift
//  trun 3
//
//  Wraps ActivityKit so RunSessionManager can be unit tested
//  by injecting a MockLiveActivityService instead.
//

import ActivityKit

// MARK: - Protocol

/// Abstraction over ActivityKit's Live Activity lifecycle.
/// Tests inject a mock; production uses DefaultLiveActivityService.
protocol LiveActivityManaging {
    func start(activityType: String, isRouteRun: Bool, pace: String) throws
    func update(distanceMiles: Double, pace: String, elapsedSeconds: Double, isPaused: Bool) async
    func end(distanceMiles: Double, pace: String, elapsedSeconds: Double)
}

// MARK: - Production Implementation

final class DefaultLiveActivityService: LiveActivityManaging {

    private var currentActivity: Activity<RunActivityAttributes>?
    private var stateObserverTask: Task<Void, Never>?

    func start(activityType: String, isRouteRun: Bool, pace: String) throws {
        let attributes = RunActivityAttributes(
            activityType: activityType,
            isRouteRun: isRouteRun
        )
        let initialState = RunActivityAttributes.ContentState(
            distanceMiles: 0,
            pace: pace,
            elapsedSeconds: 0,
            isPaused: false
        )
        let activity = try Activity.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil)
        )
        currentActivity = activity
        AppLogger.liveActivity.info("Live Activity started, id: \(activity.id)")

        // Observe iOS-initiated termination (user dismisses from lock screen, resource pressure)
        stateObserverTask?.cancel()
        stateObserverTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    AppLogger.liveActivity.info("Live Activity ended by system (state: \(String(describing: state)))")
                    self?.currentActivity = nil
                    self?.stateObserverTask = nil
                    break
                }
            }
        }
    }

    func update(distanceMiles: Double, pace: String, elapsedSeconds: Double, isPaused: Bool) async {
        guard let activity = currentActivity else { return }
        // Skip update if activity was ended by the system
        guard activity.activityState == .active else {
            currentActivity = nil
            return
        }
        let state = RunActivityAttributes.ContentState(
            distanceMiles: distanceMiles,
            pace: pace,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused
        )
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end(distanceMiles: Double, pace: String, elapsedSeconds: Double) {
        stateObserverTask?.cancel()
        stateObserverTask = nil
        guard let activity = currentActivity else { return }
        currentActivity = nil
        let finalState = RunActivityAttributes.ContentState(
            distanceMiles: distanceMiles,
            pace: pace,
            elapsedSeconds: elapsedSeconds,
            isPaused: false
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
        }
    }
}
