//
//  SharedRoute.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import Foundation

struct SharedRoute: Identifiable {
    var id: String
    var name: String
    var distanceMiles: Double
    var centerLat: Double
    var centerLon: Double
    var runCount: Int
    var createdAt: Date
}
