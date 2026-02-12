//
//  RunData.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/22/25.
//

//import SwiftUI
//import SwiftData
//import MapKit
//import AVFoundation
//import UIKit
//import Photos
//import FirebaseAuth
//import FirebaseFirestore
import UniformTypeIdentifiers

struct Run: Codable {
    var id: String?
    var time: Double
    var distance: Double
    var averagePace: String
    var caloriesBurned: Double
    var dateString: String
    var startTime: Date
}

