import Foundation
import SwiftUI

class RunSessionManager: ObservableObject {
    @Published var runData: Run = Run(time: 0, distance: 0, averagePace: "", caloriesBurned: 0, dateString: "", startTime: Date())
    @Published var currentDate: Date = Date()

    @Published var currentTimer: Double = 0.0
    @Published var isTimerPaused: Bool = false
    @Published var isPaused: Bool = false
    @Published var runStartDate: Date = Date()
    @Published var pausedDuration: Double = 0.0
    @Published var pauseStartDate: Date? = nil

    @Published var isRunDone: Bool = false
    @Published var routeCompleted: Bool = false
    @Published var isSaving: Bool = false

    @Published var prevRunDistance: Double = 0
    @Published var prevRunMinute: Int = 0
    @Published var prevRunSecond: String = ""
    @Published var prevRunMinPerMile: String = "0:00"
}
