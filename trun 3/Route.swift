//
//  Route.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/11/25.
//
import SwiftUI

class Route: Identifiable, Hashable {
    static func == (lhs: Route, rhs: Route) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
    
    // Conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    var id: Double
    var runners: [Runner]?
    var name: String
    var GPXFileURL: String
    var color: Color
    
    init(id: Double, name: String, GPXFileURL: String, color: Color) {
        self.id = id
        self.name = name
        self.GPXFileURL = GPXFileURL
        self.color = color
    }
}
