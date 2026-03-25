//
//  RouteRateLimitService.swift
//  trun 3
//

import Foundation

enum RouteRateLimitService {

    static let dailyLimit = 3

    private static let countKey = "routeGenerationCount"
    private static let dateKey  = "routeGenerationDate"

    static var remainingToday: Int {
        resetIfNewDay()
        let used = UserDefaults.standard.integer(forKey: countKey)
        return max(dailyLimit - used, 0)
    }

    static var canGenerate: Bool {
        remainingToday > 0
    }

    @discardableResult
    static func recordGeneration() -> Bool {
        resetIfNewDay()
        let used = UserDefaults.standard.integer(forKey: countKey)
        guard used < dailyLimit else { return false }
        UserDefaults.standard.set(used + 1, forKey: countKey)
        return true
    }

    // MARK: - Private

    private static func resetIfNewDay() {
        let storedDate = UserDefaults.standard.object(forKey: dateKey) as? Date
        if let storedDate, Calendar.current.isDateInToday(storedDate) {
            return
        }
        UserDefaults.standard.set(0, forKey: countKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}
