//
//  RunInfoView.swift
//  trun
//
//  Created by Sabath Rodriguez on 12/7/24.
//

import SwiftUI
import SwiftData
import MapKit
import AVFoundation
import UIKit
import Photos
import UniformTypeIdentifiers
import HealthKit
import MediaPlayer

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball: return "American Football"
        case .basketball: return "Basketball"
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .soccer: return "Soccer"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        // Add other cases as needed
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}

struct HoldToConfirmButton<Label: View>: View {
    let duration: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let backgroundColor: Color
    let progressColor: Color
    let onComplete: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressing = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.linear(duration: isPressing ? duration : 0.2), value: progress)

            // Center content
            label()
        }
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 44, pressing: { pressing in
            if pressing {
                isPressing = true
                progress = 1.0
            } else {
                // Cancelled early
                isPressing = false
                progress = 0.0
            }
        }, perform: {
            // Completed hold
            isPressing = false
            progress = 0.0
            onComplete()
        })
    }
}

struct RunInfoView: View {
    @Environment(\.modelContext) private var modelContext

    @ObservedObject var runSession: RunSessionManager

    @ObservedObject var loginManager: LoginManager
    @ObservedObject var healthStore: HealthStore
    @Binding var selectedRun: Pace?
    @Binding var runTypeDict: [Pace: Double]
    @Binding var runningMenuHeight: PresentationDetent
    @Binding var searchWasClicked: Bool
    @Binding var inRunningMode: Bool
    @ObservedObject var region: UserLocation
    @ObservedObject var liveRunService: LiveRunService

    @Binding var routes: [String: [Route]]
    @Binding var selectedRoute: Route?

    @State var searchField: String = ""

    @ObservedObject var locationManager: LocationManager

    @FocusState var isSearchFieldFocused: Bool
    @StateObject private var searchService = SharedRouteService()
    @State private var downloadingSearchRouteID: String?

    @Environment(\.colorScheme) var colorScheme

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    let generator = UISelectionFeedbackGenerator()
    private let cancelTimer = 1.5

    @State private var isCameraAvailable = false
    @State private var isImagePickerPresented = false

    @Binding var showAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertDetails: String

    @StateObject private var stravaUploadService = StravaUploadService()
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    
    private let activityTypeArray: [HKWorkoutActivityType] = [.running, .walking, .cycling]

    // Share as Route state
    @State private var showShareRoutePrompt = false
    @State private var shareRouteName = ""
    @State private var isPublishing = false
    @State private var runSaved = false
    @State private var hasSubmittedLeaderboardEntry = false
    @StateObject private var publishService = SharedRouteService()
    
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true

    private var isCompact: Bool {
        runningMenuHeight == .height(100) || runningMenuHeight == .height(200)
    }

    private var isMediumSheet: Bool {
        runningMenuHeight == .height(250) || runningMenuHeight == .height(350)
    }

    var body: some View {
        let twoDecimalPlaceRun = String(format: "%.2f", locationManager.convertToMiles())
        let minute = Int(runSession.currentTimer/60)
        let seconds = String(format: "%02d", Int(runSession.currentTimer) % 60)

        VStack(spacing: isCompact ? 10 : 20) {

            // --- STATE 1: RUN FINISHED SUMMARY ---
            if runSession.isRunDone {
                if isMediumSheet {
                    // COMPACT SUMMARY (250pt) — 2x2 grid + small buttons
                    VStack(spacing: 10) {
                        HStack(spacing: 16) {
                            CompactStat(label: "DISTANCE", value: String(format: "%.2f mi", runSession.prevRunDistance))
                            CompactStat(label: "TIME", value: "\(runSession.prevRunMinute):\(runSession.prevRunSecond)")
                        }
                        HStack(spacing: 16) {
                            CompactStat(label: runSession.activityType == .cycling ? "SPEED" : "PACE", value: runSession.activityType == .cycling ? "\(runSession.prevRunMinPerMile) mph" : "\(runSession.prevRunMinPerMile)/mi")
                            CompactStat(label: "ELEVATION", value: String(format: "%.0f ft", runSession.prevRunElevationGain * 3.28084))
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                 clearRunInformation()
                            }) {
                                Text("Discard")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundColor(.red)
                                    .cornerRadius(10)
                            }

                            Button(action: {
                                saveRunAction()
                            }) {
                                Text(runSession.isSaving ? "Saving..." : runSaved ? "Saved ✓" : "Save Run")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(runSession.isSaving || runSaved ? Color.blue.opacity(0.5) : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(runSession.isSaving || runSaved)
                        }

                        // Strava Export Button
                        if stravaAuth.isAuthenticated {
                            Button(action: {
                                exportToStrava()
                            }) {
                                HStack(spacing: 8) {
                                    if case .uploading = stravaUploadService.uploadStatus {
                                        ProgressView().tint(.white)
                                    } else if case .processing = stravaUploadService.uploadStatus {
                                        ProgressView().tint(.white)
                                    }
                                    Text(stravaButtonLabel)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(stravaButtonColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(stravaButtonDisabled)
                        }

                        // Share as Route button (free runs and unshared route runs)
                        if (selectedRoute == nil || selectedRoute?.sharedRouteID == nil) && !runSession.runLocations.isEmpty {
                            Button(action: {
                                shareRouteName = ""
                                showShareRoutePrompt = true
                            }) {
                                HStack(spacing: 8) {
                                    if isPublishing {
                                        ProgressView().tint(.white)
                                    }
                                    Text(isPublishing ? "Publishing..." : "Share as Route")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isPublishing ? Color.teal.opacity(0.5) : Color.teal)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isPublishing)
                        }
                    }
                    .padding(.horizontal)
                } else {
                // FULL SUMMARY (large sheet)
                VStack(spacing: 25) {
                    VStack(spacing: 15) {
                        SummaryRow(icon: "map.fill", title: "Distance", value: String(format: "%.2f mi", runSession.prevRunDistance))
                        SummaryRow(icon: "stopwatch.fill", title: "Time", value: "\(runSession.prevRunMinute):\(runSession.prevRunSecond)")
                        SummaryRow(icon: "speedometer", title: runSession.activityType == .cycling ? "Speed" : "Pace", value: runSession.activityType == .cycling ? "\(runSession.prevRunMinPerMile) mph" : "\(runSession.prevRunMinPerMile)/mi")
                        SummaryRow(icon: "mountain.2.fill", title: "Elevation Gain", value: String(format: "%.0f ft", runSession.prevRunElevationGain * 3.28084))
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)

                    HStack(spacing: 20) {
                        Button(action: {
                             clearRunInformation()
                        }) {
                            Text("Discard")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            saveRunAction()
                        }) {
                            Text(runSession.isSaving ? "Saving..." : runSaved ? "Saved ✓" : "Save Run")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(runSession.isSaving || runSaved ? Color.blue.opacity(0.5) : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 5)
                        }
                        .disabled(runSession.isSaving || runSaved)
                    }

                    // Strava Export Button (visible when logged into Strava and TCX data exists)
                    if stravaAuth.isAuthenticated {
                    Button(action: {
                        exportToStrava()
                    }) {
                        HStack(spacing: 8) {
                            if case .uploading = stravaUploadService.uploadStatus {
                                ProgressView()
                                    .tint(.white)
                            } else if case .processing = stravaUploadService.uploadStatus {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(stravaButtonLabel)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(stravaButtonColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(stravaButtonDisabled)
                    }

                    // Share as Route button (free runs and unshared route runs)
                    if (selectedRoute == nil || selectedRoute?.sharedRouteID == nil) && !runSession.runLocations.isEmpty {
                        Button(action: {
                            shareRouteName = ""
                            showShareRoutePrompt = true
                        }) {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isPublishing ? "Publishing..." : "Share as Route")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isPublishing ? Color.teal.opacity(0.5) : Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isPublishing)
                    }
                }
                .padding(.horizontal)
                }

            // --- STATE 2: IDLE (Pre-Run) ---
            } else if !inRunningMode {
                if isCompact {
                    // COMPACT (100pt) — just a small GO button
                    Button(action: {
                        startRun()
                    }) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                                .shadow(color: .green.opacity(0.4), radius: 6, x: 0, y: 3)

                            Text("GO")
                                .font(.system(.subheadline, design: .rounded).bold())
                                .foregroundColor(.white)
                        }
                    }
                } else {
                // Search Bar
                if searchWasClicked {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search a city or place...", text: $searchField)
                            .focused($isSearchFieldFocused)
                            .onSubmit {
                                if !searchField.trimmingCharacters(in: .whitespaces).isEmpty {
                                    searchService.searchRoutesByLocation(query: searchField)
                                }
                            }
                        if searchService.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Button("Cancel") {
                            searchField = ""
                            searchWasClicked = false
                            searchService.searchResults = []
                            runningMenuHeight = .medium
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Search Results
                    if !searchService.searchResults.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(searchService.searchResults) { route in
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
                                        if isSearchRouteAlreadyAdded(route) {
                                            Text("Added")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                                .frame(width: 60, height: 30)
                                        } else {
                                            Button(action: { downloadSearchRoute(route) }) {
                                                if downloadingSearchRouteID == route.id {
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
                                            .disabled(downloadingSearchRouteID != nil)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    } else if !searchService.isLoading && !searchField.isEmpty && searchService.searchResults.isEmpty {
                        Text("No routes found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                VStack {
                    HStack {
                        // Search Button
                        if !searchWasClicked {
                            Button(action: {
                                runningMenuHeight = .large
                                searchWasClicked = true
                                isSearchFieldFocused = true
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .padding()
                                    .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                            }
                        }

                        Spacer()

                        // START BUTTON
                        Button(action: {
                            startRun()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .green.opacity(0.4), radius: 10, x: 0, y: 5)

                                Text("GO")
                                    .font(.system(.title, design: .rounded).bold())
                                    .foregroundColor(.white)
                            }
                        }

                        Spacer()

                        // Location Button
                        Button(action: {
                            withAnimation { region.centerOnUser() }
                        }) {
                            Image(systemName: "location.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .padding()
                                .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                        }
                    }
                    .padding()


                    Picker("Select an option", selection: $runSession.activityType) {
                        ForEach(activityTypeArray, id: \.self) { option in
                            Text(option.name).tag(option).padding()
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                .padding(.horizontal)
                } // end else (full idle layout)

            // --- STATE 3: RUNNING (Active) ---
            } else {
                if isCompact {
                    // COMPACT LIVE METRICS (250pt) — horizontal stats only
                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            Text("DISTANCE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("\(twoDecimalPlaceRun) mi")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                        }

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 36)

                        VStack(spacing: 2) {
                            Text("TIME")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("\(minute):\(seconds)")
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                        }

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 36)

                        VStack(spacing: 2) {
                            Text(runSession.activityType == .cycling ? "SPEED" : "PACE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(runSession.activityType == .cycling ? "\(runSession.prevRunMinPerMile) mph" : "\(runSession.prevRunMinPerMile)/mi")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                        }
                    }
                    .padding(.vertical, 8)

                    // Compact pause button
                    Button(action: {
                        if runSession.isPaused {
                            if let pauseStart = runSession.pauseStartDate {
                                runSession.pausedDuration += Date().timeIntervalSince(pauseStart)
                            }
                            runSession.pauseStartDate = nil
                            runSession.isPaused = false
                            locationManager.startTracking()
                            runSession.isTimerPaused = false
                            runSession.updateLiveActivity(
                                distanceMiles: locationManager.convertToMiles(),
                                pace: runSession.prevRunMinPerMile,
                                elapsedSeconds: runSession.currentTimer,
                                isPaused: false
                            )
                        } else {
                            runSession.isPaused = true
                            locationManager.pauseTracking()
                            runSession.isTimerPaused = true
                            runSession.pauseStartDate = Date()
                            runSession.updateLiveActivity(
                                distanceMiles: locationManager.convertToMiles(),
                                pace: runSession.prevRunMinPerMile,
                                elapsedSeconds: runSession.currentTimer,
                                isPaused: true
                            )
                        }
                    }) {
                        Image(systemName: runSession.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(runSession.isPaused ? Color.green : Color.yellow))
                    }
                    if showMusicPlayer {
                        MusicPlayerView()
                    }
                } else {
                // LIVE METRICS
                HStack(alignment: .bottom, spacing: 30) {
                    VStack(alignment: .leading) {
                        Text("DISTANCE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Text(twoDecimalPlaceRun)
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                        Text("MILES")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading) {
                            Text("TIME")
                                .font(.caption2).bold().foregroundColor(.secondary)
                            Text("\(minute):\(seconds)")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                        }

                        VStack(alignment: .leading) {
                            Text(runSession.activityType == .cycling ? "SPEED" : "PACE")
                                .font(.caption2).bold().foregroundColor(.secondary)
                            Text(runSession.activityType == .cycling ? "\(runSession.prevRunMinPerMile) mph" : "\(runSession.prevRunMinPerMile) /mi")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                        }
                    }
                }
                .padding(.top)

                // CONTROLS (Pause/Stop/Camera) - hidden when compact
                if runningMenuHeight != .height(100) {
                HStack(spacing: 40) {
                    // Camera
                    Button(action: { isImagePickerPresented = true }) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.gray.opacity(0.5)))
                    }
                    .disabled(!isCameraAvailable)

                    // Pause / Resume / Stop Logic
                    if runSession.isPaused {
                        // HOLD TO STOP with circular progress
                        HoldToConfirmButton(
                            duration: cancelTimer,
                            size: 80,
                            lineWidth: 6,
                            backgroundColor: Color.red.opacity(0.25),
                            progressColor: .red,
                            onComplete: {
                                finishRun(minute: minute, seconds: seconds)
                                generator.selectionChanged()
                            },
                            label: {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        VStack(spacing: 2) {
                                            Text("HOLD")
                                                .font(.caption2).bold()
                                                .foregroundColor(.white)
                                            Text("STOP")
                                                .font(.caption2).bold()
                                                .foregroundColor(.white)
                                        }
                                    )
                            }
                        )

                        // RESUME BUTTON
                        Button(action: {
                            if let pauseStart = runSession.pauseStartDate {
                                runSession.pausedDuration += Date().timeIntervalSince(pauseStart)
                            }
                            runSession.pauseStartDate = nil
                            runSession.isPaused = false
                            locationManager.startTracking()
                            runSession.isTimerPaused = false
                            runSession.updateLiveActivity(
                                distanceMiles: locationManager.convertToMiles(),
                                pace: runSession.prevRunMinPerMile,
                                elapsedSeconds: runSession.currentTimer,
                                isPaused: false
                            )
                        }) {
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color.green))
                        }

                    } else {
                        // PAUSE BUTTON
                        Button(action: {
                            runSession.isPaused = true
                            locationManager.pauseTracking()
                            runSession.isTimerPaused = true
                            runSession.pauseStartDate = Date()
                            runSession.updateLiveActivity(
                                distanceMiles: locationManager.convertToMiles(),
                                pace: runSession.prevRunMinPerMile,
                                elapsedSeconds: runSession.currentTimer,
                                isPaused: true
                            )
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .yellow.opacity(0.3), radius: 8)

                                Image(systemName: "pause.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    // Location
                    Button(action: {
                        withAnimation { region.centerOnUser() }
                    }) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.blue.opacity(0.7)))
                    }
                }
                .padding(.bottom, 20)
                }
                if showMusicPlayer {
                    MusicPlayerView()
                }
                } // end else (full-size running layout)
            }
        }
        .padding()
        .onReceive(timer) { _ in
            if !runSession.isTimerPaused {
                runSession.currentTimer = Date().timeIntervalSince(runSession.runStartDate) - runSession.pausedDuration
                let rawTick = runSession.currentTimer * 10
                guard rawTick.isFinite, rawTick >= 0 else { return }
                let tick = Int(rawTick)
                // Update pace and Live Activity every 3 seconds
                if tick % 30 == 0 {
                    if runSession.activityType == .cycling {
                        runSession.prevRunMinPerMile = calculateMPH(distance: locationManager.convertToMiles(), time: runSession.currentTimer / 60)
                    } else {
                        runSession.prevRunMinPerMile = calculateMilesPerMinute(distance: locationManager.convertToMiles(), time: runSession.currentTimer / 60)
                    }
                    runSession.updateLiveActivity(
                        distanceMiles: locationManager.convertToMiles(),
                        pace: runSession.prevRunMinPerMile,
                        elapsedSeconds: runSession.currentTimer,
                        isPaused: false
                    )
                }
                // Publish location to Firebase every 5 seconds
                if tick % 50 == 0, inRunningMode, let loc = locationManager.location {
                    liveRunService.publishLocation(
                        location: loc,
                        distanceMiles: locationManager.convertToMiles(),
                        pace: runSession.prevRunMinPerMile
                    )
                }
                // Persist run snapshot every 10 seconds
                if tick % 100 == 0, inRunningMode {
                    let snapshot = runSession.buildSnapshot(locationManager: locationManager, selectedRouteID: selectedRoute?.id)
                    RunPersistenceService.save(snapshot)
                }
            }
        }
        .onChange(of: showAlert) { _ in }
        .fullScreenCover(isPresented: $isImagePickerPresented) {
            ImagePicker(sourceType: .camera) { image in
                if let image = image { saveImageToPhotoLibrary(image: image) }
            }
        }
        .onAppear { checkCameraAvailability() }
        .alert("Share as Route", isPresented: $showShareRoutePrompt) {
            TextField("Route name", text: $shareRouteName)
            Button("Share") {
                let sanitized = GPXValidator.sanitizeRouteName(shareRouteName)
                let name = sanitized.isEmpty ? "My Run" : sanitized
                shareRunAsRoute(name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give your run a name to share it as a route others can run.")
        }
    }

    // MARK: - Strava Export

    private var stravaButtonLabel: String {
        if runSession.runData.stravaActivityID != nil {
            return "Exported to Strava"
        }
        switch stravaUploadService.uploadStatus {
        case .idle: return "Export to Strava"
        case .uploading: return "Uploading..."
        case .processing: return "Processing..."
        case .success: return "Exported to Strava"
        case .error(let msg): return "Failed: \(msg)"
        }
    }

    private var stravaButtonColor: Color {
        if runSession.runData.stravaActivityID != nil {
            return Color.green
        }
        switch stravaUploadService.uploadStatus {
        case .success: return .green
        case .error: return .red
        default: return .orange
        }
    }

    private var stravaButtonDisabled: Bool {
        if runSession.runData.stravaActivityID != nil { return true }
        switch stravaUploadService.uploadStatus {
        case .uploading, .processing, .success: return true
        default: return false
        }
    }

    private func exportToStrava() {
        guard let tcx = runSession.runData.gpxString else { return }

        if !stravaAuth.isAuthenticated {
            stravaAuth.authenticate()
            return
        }

        let runName = "trun Run - \(runSession.runData.dateString)"
        Task {
            do {
                let activityID = try await stravaUploadService.uploadRun(tcxString: tcx, name: runName)
                AnalyticsService.logStravaUpload(success: true)
                await MainActor.run {
                    runSession.runData.stravaActivityID = activityID
                }
            } catch {
                AnalyticsService.logStravaUpload(success: false)
                await MainActor.run {
                    stravaUploadService.uploadStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Subviews & Logic

    func SummaryRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }

    func CompactStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    func startRun() {
        inRunningMode = true
        locationManager.distance = 0
        locationManager.startRunTracking()
        locationManager.startTracking()
        runSession.isTimerPaused = false
        runSession.isPaused = false
        runSession.currentTimer = 0
        runSession.isRunDone = false
        runSession.runData.startTime = Date()
        runSession.runStartDate = runSession.runData.startTime
        runSession.pausedDuration = 0.0
        runSession.pauseStartDate = nil

        // Start HKWorkoutSession for background protection
        healthStore.startWorkoutSession(activityType: runSession.activityType)

        AnalyticsService.logRunStarted(
            activityType: runSession.activityType.name,
            isRouteRun: selectedRoute != nil
        )

        // Start Live Activity
        runSession.startLiveActivity(activityType: runSession.activityType, isRouteRun: selectedRoute != nil)

        // Save initial snapshot so even a very early crash is recoverable
        let snapshot = runSession.buildSnapshot(locationManager: locationManager, selectedRouteID: selectedRoute?.id)
        RunPersistenceService.save(snapshot)

        // Start multiplayer session only if a route is selected
        if let route = selectedRoute {
            let routeCoords = GPXToRoute().convertGPXToRoute(filePath: route.GPXFileURL) ?? []
            liveRunService.startSession(routeID: route.id, routeCoordinates: routeCoords)
        }
    }

    func finishRun(minute: Int, seconds: String) {
        runSession.prevRunMinute = minute
        runSession.prevRunSecond = seconds
        runSession.prevRunDistance = locationManager.convertToMiles()
        runSession.prevRunElevationGain = locationManager.elevationGain

        // Check if the runner completed the selected route before stopping tracking
        if selectedRoute != nil, let loc = locationManager.location {
            let progress = liveRunService.calculateRouteProgress(currentLocation: loc.coordinate)
            runSession.routeCompleted = progress >= 0.90
        } else {
            runSession.routeCompleted = false
        }

        // Capture run locations and TCX data before stopping tracking (which resets location state)
        runSession.runLocations = locationManager.runLocations
        AppLogger.run.info("finishRun — captured \(runSession.runLocations.count) locations from LocationManager")
        locationManager.stopRunTracking()
        let elapsedSeconds = Double(minute) * 60.0 + (Double(seconds) ?? 0)
        let distanceMeters = locationManager.distance
        let tcx = locationManager.createTCXString(totalTimeSeconds: elapsedSeconds, distanceMeters: distanceMeters)
        runSession.runData.gpxString = tcx.isEmpty ? nil : tcx

        inRunningMode = false
        locationManager.stopTracking()
        runSession.isTimerPaused = true
        generator.prepare()
        generator.selectionChanged()
        runSession.isRunDone = true
        runningMenuHeight = .height(250)

        AnalyticsService.logRunCompleted(
            distanceMiles: runSession.prevRunDistance,
            durationSeconds: elapsedSeconds,
            activityType: runSession.activityType.name
        )

        // End workout session, Live Activity, and clear persistence snapshot
        healthStore.endWorkoutSession()
        runSession.endLiveActivity()
        runSession.currentTimer = 0
        RunPersistenceService.clear()

        // Stop multiplayer session
        liveRunService.stopSession()
    }

    func saveRunAction() {
        guard !runSession.isSaving else { return }
        runSession.isSaving = true

        runSession.currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        runSession.runData.averagePace = runSession.prevRunMinPerMile
        runSession.runData.distance = runSession.prevRunDistance
        runSession.runData.time = Double(runSession.prevRunMinute) + (Double(runSession.prevRunSecond) ?? 0)/60
        runSession.runData.dateString = dateFormatter.string(from: runSession.currentDate)

        AppLogger.run.info("saveRunAction — passing \(runSession.runLocations.count) locations to HealthStore")
        healthStore.saveRun(
            startTime: runSession.runData.startTime,
            endTime: Date(),
            distanceInMiles: runSession.prevRunDistance,
            calories: 0,
            activityType: runSession.activityType,
            routeLocations: runSession.runLocations,
            elevationGainMeters: runSession.prevRunElevationGain
        ) { success, error in
            if success {
                self.runSession.isSaving = false
                self.runSaved = true
                self.showAlert = true
                self.alertTitle = "Saved!"
                self.alertDetails = "Your workout was saved to Apple Health."
                self.healthStore.fetchWeeklyDistances { distances in
                    self.healthStore.weeklyDistances = distances
                }
            } else {
                self.runSession.isSaving = false
                self.showAlert = true
                self.alertTitle = "Save Failed"
                self.alertDetails = "Could not save to Apple Health. Please try again."
            }
        }

        // Save to route leaderboard in Firestore (only if a route was selected, completed, has a shared ID, and hasn't already been submitted)
        if let route = selectedRoute, runSession.routeCompleted, let sharedID = route.sharedRouteID, !hasSubmittedLeaderboardEntry {
            hasSubmittedLeaderboardEntry = true
            RouteLeaderboardService().saveCompletedRun(
                sharedRouteID: sharedID,
                time: runSession.runData.time,
                distance: runSession.prevRunDistance,
                pace: runSession.prevRunMinPerMile,
                routeProgress: 1.0
            )
        }
    }

    // MARK: - Share as Route

    private func shareRunAsRoute(name: String) {
        guard !isPublishing, !hasSubmittedLeaderboardEntry else { return }
        isPublishing = true
        hasSubmittedLeaderboardEntry = true
        runSession.isSaving = true

        let locations = runSession.runLocations
        let coordinates = locations.map { $0.coordinate }
        let gpxString = createGPXFromLocations(locations)
        let distanceMiles = runSession.prevRunDistance

        publishService.publishRoute(
            name: name,
            gpxString: gpxString,
            distanceMiles: distanceMiles,
            coordinates: coordinates
        ) { result in
            switch result {
            case .success(let docID):
                // Save GPX file locally
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filename = name.replacingOccurrences(of: " ", with: "_") + ".gpx"
                let fileURL = documentsURL.appendingPathComponent(filename)

                do {
                    try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    AppLogger.persistence.error("Error saving GPX file locally: \(error)")
                }

                // Create local route
                let allRoutes = (self.routes["My Runs"] ?? []) + (self.routes["Run Detroit"] ?? [])
                let maxId = allRoutes.map { $0.id }.max() ?? 0
                let newRoute = Route(
                    id: maxId + 1,
                    name: name,
                    GPXFileURL: fileURL.lastPathComponent,
                    color: [0.0, 0.8, 0.8],
                    sharedRouteID: docID
                )

                self.routes["My Runs"] = (self.routes["My Runs"] ?? []) + [newRoute]

                // Save first run to leaderboard, then set selectedRoute so the
                // leaderboard fetch happens AFTER the write is confirmed
                let runTime = Double(self.runSession.prevRunMinute) + (Double(self.runSession.prevRunSecond) ?? 0) / 60
                RouteLeaderboardService().saveCompletedRun(
                    sharedRouteID: docID,
                    time: runTime,
                    distance: self.runSession.prevRunDistance,
                    pace: self.runSession.prevRunMinPerMile,
                    routeProgress: 1.0
                ) {
                    // Step n is done — now move to n+1
                    self.selectedRoute = newRoute

                    // Also save to Apple Health so user doesn't need to tap "Save Run" separately
                    self.healthStore.saveRun(
                        startTime: self.runSession.runData.startTime,
                        endTime: Date(),
                        distanceInMiles: self.runSession.prevRunDistance,
                        calories: 0,
                        activityType: self.runSession.activityType,
                        routeLocations: locations,
                        elevationGainMeters: self.runSession.prevRunElevationGain
                    ) { _, _ in }

                    AnalyticsService.logRunSharedAsRoute()
                    self.isPublishing = false
                    self.clearRunInformation()
                    self.showAlert = true
                    self.alertTitle = "Route Shared!"
                    self.alertDetails = "Your run has been shared as \"\(name)\" and saved to Apple Health."
                }

            case .failure(let error):
                self.isPublishing = false
                self.runSession.isSaving = false
                self.showAlert = true
                self.alertTitle = "Share Failed"
                self.alertDetails = error.localizedDescription
            }
        }
    }

    private func createGPXFromLocations(_ locations: [CLLocation]) -> String {
        let dateFormatter = ISO8601DateFormatter()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrunApp" xmlns="http://www.topografix.com/GPX/1/1">
            <trk>
                <name>Recorded Run</name>
                <trkseg>
        """

        for loc in locations {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let ele = loc.altitude
            let time = dateFormatter.string(from: loc.timestamp)

            gpx += """

                    <trkpt lat="\(lat)" lon="\(lon)">
                        <ele>\(ele)</ele>
                        <time>\(time)</time>
                    </trkpt>
            """
        }

        gpx += """

                </trkseg>
            </trk>
        </gpx>
        """

        return gpx
    }

    private func checkCameraAvailability() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { self.isCameraAvailable = granted }
        }
    }

    private func saveImageToPhotoLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
        }
    }

    private func isSearchRouteAlreadyAdded(_ sharedRoute: SharedRoute) -> Bool {
        routes["Run Detroit"]?.contains { $0.name == sharedRoute.name } ?? false
    }

    private func downloadSearchRoute(_ sharedRoute: SharedRoute) {
        downloadingSearchRouteID = sharedRoute.id

        searchService.fetchRouteGPX(docID: sharedRoute.id) { gpxString in
            guard let gpxString = gpxString else {
                DispatchQueue.main.async { downloadingSearchRouteID = nil }
                return
            }

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = sharedRoute.name.replacingOccurrences(of: " ", with: "_") + ".gpx"
            let fileURL = documentsURL.appendingPathComponent(filename)

            do {
                try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)

                let maxId = routes["Run Detroit"]?.map { $0.id }.max() ?? 0
                let newRoute = Route(
                    id: maxId + 1,
                    name: sharedRoute.name,
                    GPXFileURL: fileURL.lastPathComponent,
                    color: [0.0, 0.5, 1.0],
                    sharedRouteID: sharedRoute.id
                )

                DispatchQueue.main.async {
                    if routes["Run Detroit"] != nil {
                        routes["Run Detroit"]?.append(newRoute)
                    } else {
                        routes["Run Detroit"] = [newRoute]
                    }
                    selectedRoute = newRoute
                    downloadingSearchRouteID = nil
                }
            } catch {
                AppLogger.routes.error("Error saving downloaded route: \(error)")
                DispatchQueue.main.async { downloadingSearchRouteID = nil }
            }
        }
    }

    private func clearRunInformation() {
        runSession.prevRunMinute = 0
        runSession.prevRunSecond = ""
        runSession.prevRunDistance = 0
        runSession.prevRunElevationGain = 0
        runSession.isRunDone = false
        runSession.routeCompleted = false
        runSession.isSaving = false
        runSession.runLocations = []
        hasSubmittedLeaderboardEntry = false
        runSaved = false
        RunPersistenceService.clear()
    }

    private func calculateMilesPerMinute(distance: Double, time: Double) -> String {
        if time <= 0 { return "0:00" }
        if distance <= 0 { return runSession.prevRunMinPerMile }

        let minutesPerMile = time / distance
        let wholeMinutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(wholeMinutes)) * 60)
        return String(format: "%d:%02d", wholeMinutes, seconds)
    }

    private func calculateMPH(distance: Double, time: Double) -> String {
        if time <= 0 || distance <= 0 { return "0.0" }
        let hours = time / 60.0
        let mph = distance / hours
        return String(format: "%.1f", mph)
    }

}

// MARK: - Music Player View
struct MusicPlayerView: View {
    @State private var isPlaying = false
    @State private var nowPlayingTitle = "Not Playing"
    @State private var nowPlayingArtist = "Select a song in Apple Music"
    
    let player = MPMusicPlayerController.systemMusicPlayer
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlayingTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text(nowPlayingArtist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            
            HStack(spacing: 20) {
                Button(action: { player.skipToPreviousItem() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.primary)
                }
                
                Button(action: {
                    if isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                
                Button(action: { player.skipToNextItem() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear {
            player.beginGeneratingPlaybackNotifications()
            updateNowPlayingInfo()
            NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { _ in
                updateNowPlayingInfo()
            }
            NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { _ in
                updateNowPlayingInfo()
            }
        }
        .onDisappear {
            player.endGeneratingPlaybackNotifications()
            NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
            NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
        }
    }
    
    private func updateNowPlayingInfo() {
        if let item = player.nowPlayingItem {
            nowPlayingTitle = item.title ?? "Unknown Title"
            nowPlayingArtist = item.artist ?? "Unknown Artist"
        } else {
            nowPlayingTitle = "Not Playing"
            nowPlayingArtist = "Select a song in Apple Music"
        }
        isPlaying = player.playbackState == .playing
    }
}
