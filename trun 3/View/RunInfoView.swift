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

struct RunInfoView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State var runData: Run
    @State var currentDate: Date
    
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
    
    @State var isPaused: Bool = false
    @State var searchField: String = ""
    
    @StateObject var locationManager = LocationManager()
    
    @FocusState var isSearchFieldFocused: Bool
    @StateObject private var searchService = SharedRouteService()
    @State private var downloadingSearchRouteID: String?
    
    @Environment(\.colorScheme) var colorScheme

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var currentTimer = 0.0
    @State private var isTimerPaused: Bool = false
    @State private var runStartDate: Date = Date()
    @State private var pausedDuration: Double = 0.0
    @State private var pauseStartDate: Date? = nil
    
    let generator = UISelectionFeedbackGenerator()
    private let cancelTimer = 1.5
    
    @State private var isCameraAvailable = false
    @State private var isImagePickerPresented = false
    
    @State var isRunDone: Bool = false
    @State var isSaving: Bool = false
    @State var prevRunDistance: Double = 0
    @State var prevRunMinute: Int = 0
    @State var prevRunSecond: String = ""
    
    @Binding var showAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertDetails: String

    @State var prevRunMinPerMile: String = "0:00"
                
    var body: some View {
        let twoDecimalPlaceRun = String(format: "%.2f", locationManager.convertToMiles())
        let minute = Int(currentTimer/60)
        let seconds = String(format: "%02d", Int(currentTimer) % 60)
        
        VStack(spacing: 20) {
            
            // --- STATE 1: RUN FINISHED SUMMARY ---
            if isRunDone {
                VStack(spacing: 25) {
                    VStack(spacing: 15) {
                        SummaryRow(icon: "map.fill", title: "Distance", value: String(format: "%.2f mi", prevRunDistance))
                        SummaryRow(icon: "stopwatch.fill", title: "Time", value: "\(prevRunMinute):\(prevRunSecond)")
                        SummaryRow(icon: "speedometer", title: "Pace", value: "\(prevRunMinPerMile)/mi")
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
                            Text(isSaving ? "Saving..." : "Save Run")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isSaving ? Color.blue.opacity(0.5) : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 5)
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal)
                
            // --- STATE 2: IDLE (Pre-Run) ---
            } else if !inRunningMode {
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
                .padding(.horizontal)
                
            // --- STATE 3: RUNNING (Active) ---
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
                            Text("PACE")
                                .font(.caption2).bold().foregroundColor(.secondary)
                            Text(prevRunMinPerMile)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                        }
                    }
                }
                .padding(.top)

                Spacer()
                
                // CONTROLS (Pause/Stop/Camera)
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
                    if isPaused {
                        // LONG PRESS TO STOP
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .stroke(Color.red, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                                
                                Text("HOLD\nSTOP")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                            }
                        }
                        .simultaneousGesture(LongPressGesture(minimumDuration: cancelTimer).onEnded { _ in
                            finishRun(minute: minute, seconds: seconds)
                        })
                        
                        // RESUME BUTTON
                        Button(action: {
                            if let pauseStart = pauseStartDate {
                                pausedDuration += Date().timeIntervalSince(pauseStart)
                            }
                            pauseStartDate = nil
                            isPaused = false
                            locationManager.startTracking()
                            isTimerPaused = false
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
                            isPaused = true
                            locationManager.pauseTracking()
                            isTimerPaused = true
                            pauseStartDate = Date()
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
        }
        .padding()
        .onReceive(timer) { _ in
            if !isTimerPaused {
                currentTimer = Date().timeIntervalSince(runStartDate) - pausedDuration
                let tick = Int(currentTimer * 10)
                // Update pace every 3 seconds
                if tick % 30 == 0 {
                    prevRunMinPerMile = calculateMilesPerMinute(distance: locationManager.convertToMiles(), time: currentTimer / 60)
                }
                // Publish location to Firebase every 5 seconds
                if tick % 50 == 0, inRunningMode, let loc = locationManager.location {
                    liveRunService.publishLocation(
                        location: loc,
                        distanceMiles: locationManager.convertToMiles(),
                        pace: prevRunMinPerMile
                    )
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertDetails), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(sourceType: .camera) { image in
                if let image = image { saveImageToPhotoLibrary(image: image) }
            }
        }
        .onAppear { checkCameraAvailability() }
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
    
    func startRun() {
        inRunningMode = true
        locationManager.distance = 0
        locationManager.startTracking()
        isTimerPaused = false
        isPaused = false
        currentTimer = 0
        isRunDone = false
        runData.startTime = Date()
        runStartDate = runData.startTime
        pausedDuration = 0.0
        pauseStartDate = nil

        // Start multiplayer session only if a route is selected
        if let route = selectedRoute {
            let routeCoords = GPXToRoute().convertGPXToRoute(filePath: route.GPXFileURL) ?? []
            liveRunService.startSession(routeID: route.id, routeCoordinates: routeCoords)
        }
    }
    
    func finishRun(minute: Int, seconds: String) {
        prevRunMinute = minute
        prevRunSecond = seconds
        prevRunDistance = locationManager.convertToMiles()
        inRunningMode = false
        locationManager.stopTracking()
        isTimerPaused = true
        currentTimer = 0
        generator.prepare()
        generator.selectionChanged()
        isRunDone = true

        // Stop multiplayer session
        liveRunService.stopSession()
    }
    
    func saveRunAction() {
        guard !isSaving else { return }
        isSaving = true

        currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        runData.averagePace = prevRunMinPerMile
        runData.distance = prevRunDistance
        runData.time = Double(prevRunMinute) + (Double(prevRunSecond) ?? 0)/60
        runData.dateString = dateFormatter.string(from: currentDate)

        Task {
            await uploadUserRun()
        }

        healthStore.saveRun(
            startTime: runData.startTime,
            endTime: Date(),
            distanceInMiles: prevRunDistance,
            calories: 0
        ) { success, error in
            if success { print("Run saved to HealthKit!") }
        }

        // Save to route leaderboard in Firestore (only if a route was selected)
        if let route = selectedRoute {
            RouteLeaderboardService().saveCompletedRun(
                routeID: route.id,
                time: runData.time,
                distance: prevRunDistance,
                pace: prevRunMinPerMile,
                routeProgress: 1.0
            )
        }
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
                    downloadingSearchRouteID = nil
                }
            } catch {
                print("Error saving downloaded route: \(error)")
                DispatchQueue.main.async { downloadingSearchRouteID = nil }
            }
        }
    }

    private func clearRunInformation() {
        prevRunMinute = 0
        prevRunSecond = ""
        prevRunDistance = 0
        isRunDone = false
        isSaving = false
    }
    
    private func calculateMilesPerMinute(distance: Double, time: Double) -> String {
        if time <= 0 { return "0:00" }
        if distance <= 0 { return prevRunMinPerMile }
        
        let minutesPerMile = time / distance
        let wholeMinutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(wholeMinutes)) * 60)
        return String(format: "%d:%02d", wholeMinutes, seconds)
    }
    
    private func uploadUserRun() async {
        modelContext.insert(runData)
        do {
            try modelContext.save()
            clearRunInformation()
            showAlert = true
            alertTitle = "Success"
            alertDetails = "Run saved!"
        } catch {
            print("Error saving run: \(error)")
        }
    }
}
