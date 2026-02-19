//
//  RouteLeaderboardView.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI
import FirebaseAuth

enum LeaderboardTab: String, CaseIterable {
    case allTime = "All Time"
    case runningNow = "Running Now"
}

struct RouteLeaderboardView: View {
    let routeID: Double
    let routeName: String
    let liveRunners: [Runner]
    let isRunning: Bool
    @StateObject private var service = RouteLeaderboardService()
    @State private var selectedTab: LeaderboardTab = .allTime

    private var currentUserID: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var sortedLiveRunners: [Runner] {
        liveRunners.sorted { $0.routeProgress > $1.routeProgress }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(routeName)
                .font(.headline)

            // Segmented toggle
            Picker("Leaderboard", selection: $selectedTab) {
                Text("All Time").tag(LeaderboardTab.allTime)
                Text("Running Now (\(liveRunners.count))").tag(LeaderboardTab.runningNow)
            }
            .pickerStyle(.segmented)

            if selectedTab == .allTime {
                allTimeContent
            } else {
                runningNowContent
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .onAppear {
            service.fetchLeaderboard(routeID: routeID)
        }
    }

    // MARK: - All Time Tab

    @ViewBuilder
    private var allTimeContent: some View {
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

    // MARK: - Running Now Tab

    @ViewBuilder
    private var runningNowContent: some View {
        if !isRunning {
            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Start a run to see other runners")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if sortedLiveRunners.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("You're the only one on this route right now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
                Text("Progress")
                    .font(.caption2).bold()
                    .frame(width: 50)
            }
            .foregroundColor(.secondary)

            ForEach(Array(sortedLiveRunners.enumerated()), id: \.element.id) { index, runner in
                HStack {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundColor(index == 0 ? .yellow : .primary)
                        .frame(width: 24)

                    Circle()
                        .fill(runner.color)
                        .frame(width: 10, height: 10)

                    Text(runner.id == currentUserID ? "You" : runner.name)
                        .font(.caption)
                        .fontWeight(runner.id == currentUserID ? .bold : .regular)

                    Spacer()

                    Text(runner.pace)
                        .font(.caption2)
                        .frame(width: 50)

                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(runner.color)
                                .frame(width: geo.size.width * runner.routeProgress)
                        }
                    }
                    .frame(width: 50, height: 6)
                }
                .padding(.vertical, 2)
                .background(runner.id == currentUserID ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ minutes: Double) -> String {
        let totalSeconds = Int(minutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
