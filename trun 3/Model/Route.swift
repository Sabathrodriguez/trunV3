//
//  Route.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/11/25.
//
import SwiftUI

struct Route: Identifiable, Hashable, Codable, Equatable {
    var id: Double
    var name: String
    var GPXFileURL: String
    var color: [Double]
    var sharedRouteID: String?
}
