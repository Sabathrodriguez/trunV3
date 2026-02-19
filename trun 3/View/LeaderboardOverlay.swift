//
//  LeaderboardOverlay.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI
import FirebaseAuth

struct LeaderboardOverlay: View {
    let runners: [Runner]

    private var currentUserID: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var sortedRunners: [Runner] {
        runners.sorted { $0.routeProgress > $1.routeProgress }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LEADERBOARD")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ForEach(Array(sortedRunners.enumerated()), id: \.element.id) { index, runner in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundColor(index == 0 ? .yellow : .primary)
                        .frame(width: 16)

                    Circle()
                        .fill(runner.color)
                        .frame(width: 10, height: 10)

                    Text(runner.id == currentUserID ? "You" : runner.name)
                        .font(.caption)
                        .fontWeight(runner.id == currentUserID ? .bold : .regular)
                        .lineLimit(1)

                    Spacer()

                    Text(runner.pace)
                        .font(.caption2)
                        .foregroundColor(.secondary)

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
                    .frame(width: 40, height: 6)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .frame(width: 220)
    }
}
