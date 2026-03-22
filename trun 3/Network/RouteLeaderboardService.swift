//
//  RouteLeaderboardService.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class RouteLeaderboardService: ObservableObject {
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    /// Save a completed run to the route's leaderboard in Firestore.
    /// The optional completion is called on the main thread once the write finishes.
    func saveCompletedRun(sharedRouteID: String, time: Double, distance: Double, pace: String, routeProgress: Double, completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        let firestore = Firestore.firestore()
        let routeKey = sharedRouteID
        let runData: [String: Any] = [
            "uid": uid,
            "time": time,
            "distance": distance,
            "pace": pace,
            "routeProgress": routeProgress,
            "date": FieldValue.serverTimestamp()
        ]

        // Ensure parent leaderboard document exists (required for subcollection queries)
        let parentRef = firestore.collection("routeLeaderboards").document(routeKey)
        parentRef.setData(["sharedRouteID": sharedRouteID], merge: true)

        parentRef.collection("runs").addDocument(data: runData) { error in
            if let error = error {
                print("Error saving run to leaderboard: \(error)")
            }

            // Increment runCount on the shared route document
            // Uses Firestore.firestore() directly so it works even if this
            // RouteLeaderboardService instance has been deallocated
            firestore.collection("sharedRoutes").document(sharedRouteID).updateData([
                "runCount": FieldValue.increment(Int64(1))
            ]) { error in
                if let error = error {
                    print("Error incrementing runCount: \(error)")
                }
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }

    /// Fetch top runs for a route by string key, sorted by time (fastest first).
    func fetchLeaderboardByKey(_ routeKey: String, limit: Int = 20) {
        isLoading = true

        db.collection("routeLeaderboards").document(routeKey).collection("runs")
            .order(by: "time", descending: false)
            .limit(to: limit)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async { self.isLoading = false }

                if let error = error {
                    print("Error fetching leaderboard: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let currentUID = Auth.auth().currentUser?.uid ?? ""
                var entries: [LeaderboardEntry] = []

                for (index, doc) in documents.enumerated() {
                    let data = doc.data()
                    let uid = data["uid"] as? String ?? ""
                    let timestamp = data["date"] as? Timestamp
                    let entry = LeaderboardEntry(
                        id: doc.documentID,
                        uid: uid,
                        rank: index + 1,
                        pace: data["pace"] as? String ?? "--:--",
                        time: data["time"] as? Double ?? 0,
                        distance: data["distance"] as? Double ?? 0,
                        date: timestamp?.dateValue() ?? Date(),
                        isCurrentUser: uid == currentUID
                    )
                    entries.append(entry)
                }

                DispatchQueue.main.async { self.leaderboard = entries }
            }
    }

    /// Fetch top runs for a route by its shared route ID.
    func fetchLeaderboard(sharedRouteID: String, limit: Int = 20) {
        fetchLeaderboardByKey(sharedRouteID, limit: limit)
    }
}
