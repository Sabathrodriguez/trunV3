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
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
    
    // Conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    var id: Double
    var name: String
    var iconID: String
    var location: CLLocationCoordinate2D
    var color: Color
    var routeID: Double
}
