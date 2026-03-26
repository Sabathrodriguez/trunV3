//
//  APIBudgetService.swift
//  trun 3
//

import Foundation
import FirebaseFirestore

class APIBudgetService {

    static let shared = APIBudgetService()

    private let db = Firestore.firestore()
    private let cacheTTL: TimeInterval = 5 * 60 // 5 minutes

    private var cachedEnabled: Bool?
    private var cacheTimestamp: Date?

    private init() {}

    /// Returns whether Google Routes API calls are allowed.
    /// Reads from Firestore `config/googleApi` with a 5-minute cache.
    /// Defaults to `true` on failure (fail-open).
    func isGoogleRoutesEnabled() async -> Bool {
        if let cached = cachedEnabled,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        do {
            let snapshot = try await db.collection("config").document("googleApi").getDocument()
            let enabled = snapshot.data()?["enabled"] as? Bool ?? true
            cachedEnabled = enabled
            cacheTimestamp = Date()
            return enabled
        } catch {
            // Fail-open: if Firestore is unreachable, allow API calls
            return true
        }
    }
}
