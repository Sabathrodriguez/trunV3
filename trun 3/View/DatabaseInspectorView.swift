//
//  DatabaseInspectorView.swift
//  trun
//
//  Created by Claude on 2/19/26.
//

import SwiftUI
import FirebaseFirestore

struct DatabaseInspectorView: View {
    @StateObject private var routeService = SharedRouteService()
    @Environment(\.dismiss) private var dismiss

    let builtInRoutes: [(id: Double, name: String)] = [
        (0, "3 mile red"), (1, "6 mile red"), (2, "10 mile red"),
        (3, "3 mile gold"), (4, "6 mile gold"), (5, "10 mile gold"),
        (6, "3 mile green"), (7, "6 mile green"), (8, "10 mile green"),
        (9, "8 mile new")
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    if routeService.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if routeService.allRoutes.isEmpty {
                        Text("No shared routes found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(routeService.allRoutes) { route in
                            NavigationLink {
                                SharedRouteDetailView(route: route)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.name)
                                        .font(.headline)
                                    HStack {
                                        Text(String(format: "%.2f mi", route.distanceMiles))
                                        Text("·")
                                        Text("\(route.runCount) runs")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Text(route.id)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Shared Routes (\(routeService.allRoutes.count))")
                        Spacer()
                        Button("Refresh") { routeService.fetchAllRoutes() }
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                Section("Built-in Route Leaderboards") {
                    ForEach(builtInRoutes, id: \.id) { route in
                        NavigationLink(route.name) {
                            LeaderboardDetailView(
                                routeKey: String(Int(route.id)),
                                routeName: route.name
                            )
                        }
                    }
                }
            }
            .navigationTitle("DB Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { routeService.fetchAllRoutes() }
        }
    }
}

// MARK: - Shared Route Detail

struct SharedRouteDetailView: View {
    let route: SharedRoute
    @StateObject private var leaderboardService = RouteLeaderboardService()

    var body: some View {
        List {
            Section("Route Metadata") {
                LabeledContent("Doc ID", value: route.id)
                LabeledContent("Name", value: route.name)
                LabeledContent("Distance", value: String(format: "%.2f mi", route.distanceMiles))
                LabeledContent("Run Count", value: "\(route.runCount)")
                LabeledContent("Center Lat", value: String(format: "%.6f", route.centerLat))
                LabeledContent("Center Lon", value: String(format: "%.6f", route.centerLon))
                LabeledContent("Created", value: route.createdAt.formatted())
            }

            Section {
                if leaderboardService.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if leaderboardService.leaderboard.isEmpty {
                    Text("No leaderboard entries")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(leaderboardService.leaderboard) { entry in
                        LeaderboardEntryRow(entry: entry)
                    }
                }
            } header: {
                Text("Leaderboard (routes/\(route.id)/runs)")
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            leaderboardService.fetchLeaderboardByKey(route.id)
        }
    }
}

// MARK: - Built-in Leaderboard Detail

struct LeaderboardDetailView: View {
    let routeKey: String
    let routeName: String
    @StateObject private var service = RouteLeaderboardService()

    var body: some View {
        List {
            Section {
                if service.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if service.leaderboard.isEmpty {
                    Text("No entries yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(service.leaderboard) { entry in
                        LeaderboardEntryRow(entry: entry)
                    }
                }
            } header: {
                Text("Firestore: routes/\(routeKey)/runs (\(service.leaderboard.count) entries)")
            }
        }
        .navigationTitle(routeName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.fetchLeaderboardByKey(routeKey) }
    }
}

// MARK: - Leaderboard Entry Row

struct LeaderboardEntryRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(entry.rank)")
                    .font(.headline)
                    .foregroundColor(entry.isCurrentUser ? .blue : .primary)
                Spacer()
                Text(String(format: "%.1f min", entry.time))
                    .font(.subheadline.bold())
            }
            HStack {
                Text(entry.pace + "/mi")
                Text("·")
                Text(String(format: "%.2f mi", entry.distance))
                Text("·")
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            Text("UID: \(String(entry.uid.prefix(12)))...")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
    }
}
