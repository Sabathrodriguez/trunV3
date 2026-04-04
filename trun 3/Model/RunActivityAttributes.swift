import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMiles: Double
        var pace: String
        var timerDate: Date  // virtual start = Date() - elapsedSeconds, accounts for pauses
        var isPaused: Bool
        var elapsedSeconds: Double  // frozen value for static display when paused
    }

    var activityType: String
    var isRouteRun: Bool
}
