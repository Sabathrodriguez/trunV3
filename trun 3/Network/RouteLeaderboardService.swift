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
    func saveCompletedRun(routeID: Double, time: Double, distance: Double, pace: String, routeProgress: Double) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let routeKey = String(Int(routeID))
        let data: [String: Any] = [
            "uid": uid,
            "time": time,
            "distance": distance,
            "pace": pace,
            "routeProgress": routeProgress,
            "date": FieldValue.serverTimestamp()
        ]

        db.collection("routes").document(routeKey).collection("runs").addDocument(data: data) { error in
            if let error = error {
                print("Error saving run to leaderboard: \(error)")
            }
        }
    }

    /// Fetch top runs for a route, sorted by time (fastest first).
    func fetchLeaderboard(routeID: Double, limit: Int = 20) {
        let routeKey = String(Int(routeID))
        isLoading = true

        db.collection("routes").document(routeKey).collection("runs")
            .order(by: "time", descending: false)
            .limit(to: limit)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    self.isLoading = false
                }

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

                DispatchQueue.main.async {
                    self.leaderboard = entries
                }
            }
    }
}
