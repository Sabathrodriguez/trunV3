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
    var gpxString: String?
    var stravaActivityID: String?

    init(id: String? = nil, time: Double, distance: Double, averagePace: String, caloriesBurned: Double, dateString: String, startTime: Date, gpxString: String? = nil, stravaActivityID: String? = nil) {
        self.id = id
        self.time = time
        self.distance = distance
        self.averagePace = averagePace
        self.caloriesBurned = caloriesBurned
        self.dateString = dateString
        self.startTime = startTime
        self.gpxString = gpxString
        self.stravaActivityID = stravaActivityID
    }
}

