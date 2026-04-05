import FirebaseAnalytics

/// Centralized event-based analytics tracking via Firebase Analytics.
/// All events are no-ops when the user has not granted consent
/// (collection is disabled at the Firebase SDK level by AnalyticsConsentManager).
enum AnalyticsService {

    // MARK: - Auth

    static func logSignUp(method: String) {
        Analytics.logEvent(AnalyticsEventSignUp, parameters: [
            AnalyticsParameterMethod: method
        ])
    }

    static func logLogin(method: String) {
        Analytics.logEvent(AnalyticsEventLogin, parameters: [
            AnalyticsParameterMethod: method
        ])
    }

    static func logLogout() {
        Analytics.logEvent("logout", parameters: nil)
    }

    // MARK: - Runs

    static func logRunStarted(activityType: String, isRouteRun: Bool) {
        Analytics.logEvent("run_started", parameters: [
            "activity_type": activityType,
            "is_route_run": isRouteRun
        ])
    }

    static func logRunCompleted(distanceMiles: Double, durationSeconds: Double, activityType: String) {
        Analytics.logEvent("run_completed", parameters: [
            "distance_miles": distanceMiles,
            "duration_seconds": durationSeconds,
            "activity_type": activityType
        ])
    }

    static func logRunResumed() {
        Analytics.logEvent("run_resumed", parameters: nil)
    }

    // MARK: - Routes

    static func logRouteGenerated(distanceMiles: Double, routeType: String) {
        Analytics.logEvent("route_generated", parameters: [
            "distance_miles": distanceMiles,
            "route_type": routeType
        ])
    }

    static func logRouteSaved() {
        Analytics.logEvent("route_saved", parameters: nil)
    }

    static func logRouteShared() {
        Analytics.logEvent("route_shared", parameters: nil)
    }

    static func logRouteImported() {
        Analytics.logEvent("route_imported", parameters: nil)
    }

    // MARK: - Social / Sharing

    static func logRunSharedAsRoute() {
        Analytics.logEvent("run_shared_as_route", parameters: nil)
    }

    static func logLeaderboardViewed(routeID: String) {
        Analytics.logEvent("leaderboard_viewed", parameters: [
            "route_id": routeID
        ])
    }

    // MARK: - Integrations

    static func logStravaConnected() {
        Analytics.logEvent("strava_connected", parameters: nil)
    }

    static func logStravaUpload(success: Bool) {
        Analytics.logEvent("strava_upload", parameters: [
            "success": success
        ])
    }

    // MARK: - Profile

    static func logUsernameSet() {
        Analytics.logEvent("username_set", parameters: nil)
    }

    static func logProfilePhotoChanged() {
        Analytics.logEvent("profile_photo_changed", parameters: nil)
    }

    // MARK: - Screens

    static func logScreenView(name: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name
        ])
    }
}
