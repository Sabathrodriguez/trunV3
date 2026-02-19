//
//  Runner.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/11/25.
//
import MapKit
import SwiftUI

struct Runner: Identifiable, Hashable {
    static func == (lhs: Runner, rhs: Runner) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String
    var name: String
    var iconID: String
    var location: CLLocationCoordinate2D
    var color: Color
    var routeID: String
    var routeProgress: Double
    var pace: String
    var distanceMiles: Double

    /// Initialize from Firebase RTDB snapshot data.
    /// Only 4 fields come from Firebase (la, lo, p, t). Everything else is derived client-side.
    init(id: String, data: [String: Any], routeID: String, runnerIndex: Int) {
        self.id = id
        self.name = "Runner \(runnerIndex + 1)"
        self.iconID = ""
        let lat = data["la"] as? Double ?? 0
        let lon = data["lo"] as? Double ?? 0
        self.location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.color = Color.fromUID(id)
        self.routeID = routeID
        self.routeProgress = data["p"] as? Double ?? 0
        self.pace = "--:--"
        self.distanceMiles = 0
    }

    /// Manual initializer for local use and testing.
    init(id: String, name: String, iconID: String = "", location: CLLocationCoordinate2D,
         color: Color, routeID: String, routeProgress: Double = 0,
         pace: String = "--:--", distanceMiles: Double = 0) {
        self.id = id
        self.name = name
        self.iconID = iconID
        self.location = location
        self.color = color
        self.routeID = routeID
        self.routeProgress = routeProgress
        self.pace = pace
        self.distanceMiles = distanceMiles
    }
}
