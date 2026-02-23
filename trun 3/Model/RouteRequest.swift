import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
enum RouteType: String, Codable, CaseIterable {
    case loop
    case outAndBack
    case pointToPoint
}

@available(iOS 26.0, *)
@Generable
enum ActivityType: String, Codable, CaseIterable {
    case running
    case walking
    case cycling
}

@available(iOS 26.0, *)
@Generable
struct RouteRequest {
    /// Target distance in miles
    var targetDistanceMiles: Double
    /// Type of route: loop returns to start, outAndBack goes and returns same way, pointToPoint goes one direction
    var routeType: RouteType
    /// Activity type: walking or cycling
    var activityType: ActivityType
    /// Optional direction preference from the user such as toward downtown or along the river
    var directionPreference: String?
    /// Optional terrain preference such as flat or hilly
    var terrainPreference: String?
}
