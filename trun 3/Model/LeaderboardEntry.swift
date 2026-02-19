//
//  LeaderboardEntry.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import Foundation

struct LeaderboardEntry: Identifiable {
    var id: String
    var uid: String
    var rank: Int
    var pace: String
    var time: Double
    var distance: Double
    var date: Date
    var isCurrentUser: Bool
}
