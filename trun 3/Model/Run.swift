//
//  RunData.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/22/25.
//

import SwiftData
import UniformTypeIdentifiers

@Model
final class Run {
    var id: String?
    var time: Double
    var distance: Double
    var averagePace: String
    var caloriesBurned: Double
    var dateString: String
    var startTime: Date

    init(id: String? = nil, time: Double, distance: Double, averagePace: String, caloriesBurned: Double, dateString: String, startTime: Date) {
        self.id = id
        self.time = time
        self.distance = distance
        self.averagePace = averagePace
        self.caloriesBurned = caloriesBurned
        self.dateString = dateString
        self.startTime = startTime
    }
}

