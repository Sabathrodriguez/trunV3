import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMiles: Double
        var pace: String
        var elapsedSeconds: Double
        var isPaused: Bool
    }

    var activityType: String
    var isRouteRun: Bool
}
