//
//  SharedRouteLibraryView.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI
import CoreLocation

struct SharedRouteLibraryView: View {
    @StateObject private var service = SharedRouteService()
    @ObservedObject var userLocation: UserLocation
    @Binding var routes: [String: [Route]]
    @Binding var selectedRoute: Route

    @State private var showShareAlert = false
    @State private var downloadingRouteID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Routes")
                    .font(.headline)
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if service.nearbyRoutes.isEmpty && !service.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No shared routes nearby")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Record a route and share it with the community!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(service.nearbyRoutes) { route in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)

                                    HStack(spacing: 12) {
                                        Label(String(format: "%.1f mi", route.distanceMiles), systemImage: "ruler")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        Label("\(route.runCount) runs", systemImage: "figure.run")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if isRouteAlreadyAdded(route) {
                                    Text("Added")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                        .frame(width: 60, height: 30)
                                } else {
                                    Button(action: {
                                        downloadRoute(route)
                                    }) {
                                        if downloadingRouteID == route.id {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 60, height: 30)
                                        } else {
                                            Text("Add")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .frame(width: 60, height: 30)
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .disabled(downloadingRouteID != nil)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .onAppear {
            fetchRoutes()
        }
    }

    private func fetchRoutes() {
        guard let location = userLocation.locationManager?.location else { return }
        service.fetchNearbyRoutes(
            userLat: location.coordinate.latitude,
            userLon: location.coordinate.longitude
        )
    }

    private func isRouteAlreadyAdded(_ sharedRoute: SharedRoute) -> Bool {
        routes["Run Detroit"]?.contains { $0.name == sharedRoute.name } ?? false
    }

    private func downloadRoute(_ sharedRoute: SharedRoute) {
        downloadingRouteID = sharedRoute.id

        service.fetchRouteGPX(docID: sharedRoute.id) { gpxString in
            guard let gpxString = gpxString else {
                DispatchQueue.main.async { downloadingRouteID = nil }
                return
            }

            // Save GPX to documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = sharedRoute.name.replacingOccurrences(of: " ", with: "_") + ".gpx"
            let fileURL = documentsURL.appendingPathComponent(filename)

            do {
                try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)

                let maxId = routes["Run Detroit"]?.map { $0.id }.max() ?? 0
                let newRoute = Route(
                    id: maxId + 1,
                    name: sharedRoute.name,
                    GPXFileURL: fileURL.path,
                    color: [0.0, 0.5, 1.0]
                )

                DispatchQueue.main.async {
                    if routes["Run Detroit"] != nil {
                        routes["Run Detroit"]?.append(newRoute)
                    } else {
                        routes["Run Detroit"] = [newRoute]
                    }
                    selectedRoute = newRoute
                    downloadingRouteID = nil
                }
            } catch {
                print("Error saving downloaded route: \(error)")
                DispatchQueue.main.async { downloadingRouteID = nil }
            }
        }
    }
}
