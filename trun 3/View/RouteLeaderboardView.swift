//
//  RouteLeaderboardView.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI

struct RouteLeaderboardView: View {
    let routeID: Double
    let routeName: String
    @StateObject private var service = RouteLeaderboardService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fastest Runs")
                .font(.headline)

            Text(routeName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if service.leaderboard.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No runs yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Be the first to complete this route!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Header row
                HStack {
                    Text("#")
                        .font(.caption2).bold()
                        .frame(width: 24)
                    Text("Runner")
                        .font(.caption2).bold()
                    Spacer()
                    Text("Pace")
                        .font(.caption2).bold()
                        .frame(width: 50)
                    Text("Time")
                        .font(.caption2).bold()
                        .frame(width: 60)
                }
                .foregroundColor(.secondary)

                ForEach(service.leaderboard) { entry in
                    HStack {
                        Text("\(entry.rank)")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundColor(entry.rank <= 3 ? .yellow : .primary)
                            .frame(width: 24)

                        Circle()
                            .fill(Color.fromUID(entry.uid))
                            .frame(width: 10, height: 10)

                        Text(entry.isCurrentUser ? "You" : "Runner")
                            .font(.caption)
                            .fontWeight(entry.isCurrentUser ? .bold : .regular)

                        Spacer()

                        Text("\(entry.pace)/mi")
                            .font(.caption2)
                            .frame(width: 50)

                        Text(formatTime(entry.time))
                            .font(.caption2)
                            .frame(width: 60)
                    }
                    .padding(.vertical, 2)
                    .background(entry.isCurrentUser ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .onAppear {
            service.fetchLeaderboard(routeID: routeID)
        }
    }

    private func formatTime(_ minutes: Double) -> String {
        let totalSeconds = Int(minutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
