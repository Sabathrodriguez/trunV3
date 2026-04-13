//
//  ContentView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 11/16/24.
//

import SwiftUI
import SwiftData
import MapKit
import FirebaseFirestore
import UniformTypeIdentifiers
import HealthKit
import CoreLocation

// Define GPX Document structure for FileExporter
struct GPXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "gpx") ?? .xml] }
    
    var text: String
    
    init(text: String = "") {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            self.text = String(decoding: data, as: UTF8.self)
        } else {
            self.text = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    var routeConverter:GPXToRoute = GPXToRoute()
    
    @ObservedObject var healthStore = HealthStore()
        
    @ObservedObject public var loginManager: LoginManager
    @StateObject var liveRunService = LiveRunService()
    @StateObject private var uploadService = SharedRouteService()
    @StateObject var runSession = RunSessionManager()
    @State var inRunningMode: Bool = false
    @Environment(\.scenePhase) var scenePhase
    @State private var showRecoveryAlert = false
    @State private var recoveredSnapshot: RunSnapshot?

    let db = Firestore.firestore()
    
    @State var routes: [String: [Route]] = ContentView.loadInitialRoutes()

    private static let defaultRoutes: [Route] = []

    private static func loadInitialRoutes() -> [String: [Route]] {
        var routes = ["Run Detroit": defaultRoutes, "My Runs": [Route]()]
        if let saved = RouteStorageService.loadRoutes() {
            routes.merge(saved) { _, saved in saved }
        }
        return routes
    }
    
    @State var selectedRoute: Route? = nil
    
    @State var selectedRun: Pace? = .CurrentMile
    
    // this will need to be updated to retrieve actual run values
    @State var runTypeDict: [Pace: Double] = [Pace.Average: 1, Pace.Current: 2, Pace.CurrentMile: 3]
    @State var showSheet: Bool = false
    @State var runningMenuHeight: PresentationDetent = PresentationDetent.height(250)
    @State var searchWasClicked: Bool = false
    
    @State var showAlert: Bool = false
    @State var alertTitle: String = ""
    @State var alertDetails: String = ""
    
    var iconHeightAndWidth: CGFloat = 75
    
    // State for file importer/exporter
    @State private var showDBInspector = false
    @State private var showRouteNamePrompt = false
    @State private var routeName = ""
    @State private var pendingGPXString = ""
    @State private var pendingCoords: [CLLocationCoordinate2D] = []
    @State private var pendingDistance: Double = 0
    @State private var isProcessingGPX = false
    @State private var isUploadImporterPresented = false
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var gpxDocument: GPXDocument?
    @State private var showRouteGenerator = false
    @State private var showProfile = false
    @State private var cachedRouteCoords: [CLLocationCoordinate2D]? = nil
    @State private var completedRunCoords: [CLLocationCoordinate2D]? = nil
    @StateObject private var profileService = ProfileService()
    
    // We can use the LocationManager from the view model if it's accessible,
    // but the provided UserLocation class seems separate. 
    // Assuming we should use a LocationManager instance here for recording:
    @StateObject var locationManager = LocationManager()
    
    @StateObject var viewModel: UserLocation = UserLocation()
    
    // With this computed property:
    var runningMenuHeights: Set<PresentationDetent> {
        if inRunningMode {
            return [.height(350), .height(200), .large] // Increased by 100
        } else {
            return [.height(250), .height(100), .large]
        }
    }
    
    var body: some View {
            ZStack {
                // MAP LAYER
                Map(position: $viewModel.regionView) {
                    UserAnnotation()
                    
                    if selectedRoute != nil,
                       let coords = cachedRouteCoords,
                       !coords.isEmpty {
                        // Rainbow route segments
                        ForEach(RouteAnnotationHelpers.rainbowSegments(from: coords)) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(segment.color, lineWidth: 5)
                        }

                        // Start annotation
                        Annotation("Start", coordinate: coords.first!) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                            }
                        }

                        // End annotation
                        Annotation("Finish", coordinate: coords.last!) {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 20))
                                .shadow(radius: 2)
                        }

                        // Directional arrows
                        ForEach(RouteAnnotationHelpers.generateArrows(from: coords)) { arrow in
                            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                                Image(systemName: "arrowtriangle.forward.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .shadow(color: .black, radius: 1)
                                    .rotationEffect(.degrees(arrow.bearing - 90))
                            }
                        }
                    }
                    
                    // Completed run route overlay
                    if let coords = completedRunCoords, coords.count >= 2, runSession.isRunDone {
                        ForEach(RouteAnnotationHelpers.rainbowSegments(from: coords)) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(segment.color, lineWidth: 5)
                        }

                        Annotation("Start", coordinate: coords.first!) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                            }
                        }

                        Annotation("Finish", coordinate: coords.last!) {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 20))
                                .shadow(radius: 2)
                        }

                        ForEach(RouteAnnotationHelpers.generateArrows(from: coords)) { arrow in
                            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                                Image(systemName: "arrowtriangle.forward.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .shadow(color: .black, radius: 1)
                                    .rotationEffect(.degrees(arrow.bearing - 90))
                            }
                        }
                    }

                    ForEach(liveRunService.liveRunners.filter { $0.name != "You" }) { runner in
                        Annotation(runner.name, coordinate: runner.location) {
                            RunnerAnnotationView(runner: runner)
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                }
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    viewModel.checkIfLocationServicesEnabled()
                    profileService.fetchProfileImageURL()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        requestHealthKitAccess()
                    }
                    // Clean up any ghost runner entries from prior crashes
                    liveRunService.cleanupOwnStaleEntries()
                    // Present the main sheet after the view hierarchy is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSheet = true
                    }
                    // Check for interrupted run — the alert is inside the sheet
                    // content, so it presents from the sheet controller (no collision)
                    if let snapshot = RunPersistenceService.load() {
                        recoveredSnapshot = snapshot
                        showRecoveryAlert = true
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background && inRunningMode {
                        let snapshot = runSession.buildSnapshot(locationManager: locationManager, selectedRouteID: selectedRoute?.id)
                        RunPersistenceService.save(snapshot)
                    }
                    // Restore the main sheet if it was lost during a background cycle
                    if newPhase == .active && !showSheet {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSheet = true
                        }
                    }
                }
                .onChange(of: selectedRoute) { _ in
                    viewModel.centerOnUser()
                    // Recompute cached route coordinates
                    if let route = selectedRoute {
                        cachedRouteCoords = routeConverter.convertGPXToRoute(filePath: route.GPXFileURL)
                    } else {
                        cachedRouteCoords = nil
                    }
                    // Keep the sheet expanded when selecting a route from the list
                    if runningMenuHeight == .large {
                        DispatchQueue.main.async {
                            runningMenuHeight = .large
                        }
                    }
                }
                .onChange(of: routes) { _ in
                    RouteStorageService.saveRoutes(routes)
                }
                .onChange(of: runSession.isRunDone) { isDone in
                    if isDone && !runSession.runLocations.isEmpty {
                        let coords = runSession.runLocations.map { $0.coordinate }
                        completedRunCoords = coords

                        // Zoom map to fit the completed route, offset for the 250pt bottom sheet
                        let lats = coords.map { $0.latitude }
                        let lons = coords.map { $0.longitude }
                        if let minLat = lats.min(), let maxLat = lats.max(),
                           let minLon = lons.min(), let maxLon = lons.max() {
                            let latDelta = (maxLat - minLat) * 1.3 + 0.002
                            let lonDelta = (maxLon - minLon) * 1.3 + 0.002
                            let routeCenterLat = (minLat + maxLat) / 2
                            let routeCenterLon = (minLon + maxLon) / 2

                            // Shift center upward so the route is centered in the visible area above the sheet
                            // The 250pt sheet covers roughly 30% of the screen height, so shift by ~30% of the lat span
                            let sheetOffsetFraction = 0.3
                            let adjustedCenterLat = routeCenterLat + latDelta * sheetOffsetFraction / 2

                            let center = CLLocationCoordinate2D(
                                latitude: adjustedCenterLat,
                                longitude: routeCenterLon
                            )
                            let span = MKCoordinateSpan(
                                latitudeDelta: latDelta,
                                longitudeDelta: lonDelta
                            )
                            let region = MKCoordinateRegion(center: center, span: span)
                            withAnimation {
                                viewModel.regionView = .region(region)
                            }
                        }
                    } else if !isDone {
                        completedRunCoords = nil
                    }
                }

                // PROFILE BUTTON OVERLAY
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            showProfile = true
                            showDBInspector = false
                            runningMenuHeight = .large
                        }) {
                            if let urlString = profileService.profileImageURL,
                               let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                            .shadow(radius: 4)
                                    default:
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.white)
                                            .shadow(radius: 4)
                                    }
                                }
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 50)
                    }
                    Spacer()
                }

                // LEADERBOARD OVERLAY (visible during active runs)
                if inRunningMode && !liveRunService.liveRunners.isEmpty {
                    VStack {
                        HStack {
                            LeaderboardOverlay(runners: liveRunService.liveRunners)
                                .padding(.leading, 16)
                                .padding(.top, 90)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // UI OVERLAY LAYER
                VStack {
                    Spacer()
                }
                .sheet(isPresented: $showSheet) {
                    ZStack {
                        // Custom Background for Sheet
                        Color(UIColor.systemBackground).opacity(0.8)
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {                    

                            RunView(
                                selectedRun: $selectedRun,
                                runTypeDict: $runTypeDict,
                                runningMenuHeight: $runningMenuHeight,
                                searchWasClicked: $searchWasClicked,
                                userRegion: viewModel,
                                inRunningMode: $inRunningMode,
                                loginManager: loginManager,
                                liveRunService: liveRunService,
                                healthStore: healthStore,
                                locationManager: locationManager,
                                runSession: runSession,
                                routes: $routes,
                                selectedRoute: $selectedRoute,
                                showAlert: $showAlert,
                                alertTitle: $alertTitle,
                                alertDetails: $alertDetails
                            )
                            
                            // EXPANDED CONTENT (Visible when expanded)
                            if runningMenuHeight == .large {
                                if showProfile {
                                    ProfileView(
                                        profileService: profileService,
                                        loginManager: loginManager,
                                        isPresented: $showProfile,
                                        showDBInspector: $showDBInspector
                                    )
                                } else if showDBInspector {
                                    DatabaseInspectorView(isPresented: $showDBInspector)
                                } else if showRouteGenerator {
                                    if #available(iOS 26.0, *) {
                                        RouteGeneratorView(
                                            routes: $routes,
                                            selectedRoute: $selectedRoute,
                                            isPresented: $showRouteGenerator,
                                            userLocation: viewModel.locationManager?.location?.coordinate
                                        )
                                    }
                                } else {
                                    ScrollView(.vertical, showsIndicators: true) {
                                        VStack(spacing: 16) {

                                            WeeklyActivityView(
                                            runMiles: healthStore.weeklyDistances[.running] ?? 0,
                                            cycleMiles: healthStore.weeklyDistances[.cycling] ?? 0,
                                            walkMiles: healthStore.weeklyDistances[.walking] ?? 0
                                        )
                    .padding(.bottom, 4)
                                // MY ROUTES
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("My Routes")
                                            .font(.headline)

                                        if let routeList = routes["Run Detroit"], !routeList.isEmpty {
                                            ScrollView(.vertical, showsIndicators: false) {
                                                VStack(spacing: 6) {
                                                    // NO ROUTE option
                                                    HStack {
                                                        Circle()
                                                            .fill(Color.gray)
                                                            .frame(width: 12, height: 12)

                                                        Text("No Route")
                                                            .font(.subheadline)
                                                            .fontWeight(selectedRoute == nil ? .bold : .regular)
                                                            .lineLimit(1)

                                                        Spacer()

                                                        if selectedRoute == nil {
                                                            Text("Active")
                                                                .font(.caption2)
                                                                .fontWeight(.bold)
                                                                .foregroundColor(.green)
                                                                .padding(.horizontal, 8)
                                                                .padding(.vertical, 3)
                                                                .background(Color.green.opacity(0.15))
                                                                .cornerRadius(6)
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .fill(selectedRoute == nil ? Color.blue.opacity(0.1) : Color.clear)
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 10)
                                                                    .stroke(selectedRoute == nil ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                                                            )
                                                    )
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        selectedRoute = nil
                                                    }

                                                    ForEach(routeList) { route in
                                                        HStack {
                                                            // Color dot
                                                            Circle()
                                                                .fill(Color(red: route.color[0], green: route.color[1], blue: route.color[2]))
                                                                .frame(width: 12, height: 12)

                                                            Text(route.name)
                                                                .font(.subheadline)
                                                                .fontWeight(selectedRoute?.id == route.id ? .bold : .regular)
                                                                .lineLimit(1)

                                                            Spacer()

                                                            if selectedRoute?.id == route.id {
                                                                Text("Active")
                                                                    .font(.caption2)
                                                                    .fontWeight(.bold)
                                                                    .foregroundColor(.green)
                                                                    .padding(.horizontal, 8)
                                                                    .padding(.vertical, 3)
                                                                    .background(Color.green.opacity(0.15))
                                                                    .cornerRadius(6)
                                                            }

                                                            // Remove route from list
                                                            Button(action: {
                                                                removeRouteFromList(route)
                                                            }) {
                                                                Image(systemName: "xmark.circle.fill")
                                                                    .font(.body)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        }
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 8)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 10)
                                                                .fill(selectedRoute?.id == route.id ? Color.blue.opacity(0.1) : Color.clear)
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 10)
                                                                        .stroke(selectedRoute?.id == route.id ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                                                                )
                                                        )
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            selectedRoute = route
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            Text("No routes added yet")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 20)
                                        }
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(16)

                                // MY RUNS (routes created from free runs)
                                if let myRuns = routes["My Runs"], !myRuns.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("My Runs")
                                            .font(.headline)

                                        ScrollView(.vertical, showsIndicators: false) {
                                            VStack(spacing: 6) {
                                                ForEach(myRuns) { route in
                                                    HStack {
                                                        Circle()
                                                            .fill(Color(red: route.color[0], green: route.color[1], blue: route.color[2]))
                                                            .frame(width: 12, height: 12)

                                                        Text(route.name)
                                                            .font(.subheadline)
                                                            .fontWeight(selectedRoute?.id == route.id ? .bold : .regular)
                                                            .lineLimit(1)

                                                        Spacer()

                                                        if selectedRoute?.id == route.id {
                                                            Text("Active")
                                                                .font(.caption2)
                                                                .fontWeight(.bold)
                                                                .foregroundColor(.green)
                                                                .padding(.horizontal, 8)
                                                                .padding(.vertical, 3)
                                                                .background(Color.green.opacity(0.15))
                                                                .cornerRadius(6)
                                                        }

                                                        Button(action: {
                                                            removeMyRun(route)
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .font(.body)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .fill(selectedRoute?.id == route.id ? Color.blue.opacity(0.1) : Color.clear)
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 10)
                                                                    .stroke(selectedRoute?.id == route.id ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                                                            )
                                                    )
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        selectedRoute = route
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(16)
                                }

                                // ROUTE LEADERBOARD
                                if let route = selectedRoute {
                                    RouteLeaderboardView(
                                        routeID: route.id,
                                        routeName: route.name,
                                        sharedRouteID: route.sharedRouteID,
                                        liveRunners: liveRunService.liveRunners,
                                        isRunning: inRunningMode
                                    )
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "trophy")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                        Text("Select a Route")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        Text("Choose a route to see its leaderboard")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 30)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(16)
                                }

                                // SHARED ROUTE LIBRARY
                                SharedRouteLibraryView(
                                    userLocation: viewModel,
                                    routes: $routes,
                                    selectedRoute: $selectedRoute
                                )

                                // IMPORT / EXPORT / SHARE CONTROLS
                                VStack(spacing: 10) {
                                    // Import Button (local only)
                                    Button(action: { isFileImporterPresented = true }) {
                                        Label("Import", systemImage: "folder.badge.plus")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.blue)
                                            .cornerRadius(12)
                                    }
                                    .fileImporter(
                                        isPresented: $isFileImporterPresented,
                                        allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                                        allowsMultipleSelection: false
                                    ) { result in
                                        if case .success(let urls) = result, let url = urls.first {
                                            importGPX(from: url)
                                        }
                                    }

                                    // Upload GPX to Firestore
                                    Button(action: { isUploadImporterPresented = true }) {
                                        Label("Upload", systemImage: "icloud.and.arrow.up")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.green)
                                            .cornerRadius(12)
                                    }
                                    .fileImporter(
                                        isPresented: $isUploadImporterPresented,
                                        allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                                        allowsMultipleSelection: false
                                    ) { result in
                                        if case .success(let urls) = result, let url = urls.first {
                                            uploadGPXToFirestore(from: url)
                                        }
                                    }

                                    // Record/Save Button
                                //     Button(action: {
                                //         if locationManager.isRecording {
                                //             locationManager.stopRecording()
                                //             isProcessingGPX = true

                                //             Task {
                                //                 let gpxString = locationManager.createGPXString()
                                //                 let coords = GPXParser().parse(gpxString: gpxString)
                                //                 let distance = locationManager.convertToMiles()

                                //                 await MainActor.run {
                                //                     if !gpxString.isEmpty {
                                //                         pendingGPXString = gpxString
                                //                         pendingCoords = coords
                                //                         pendingDistance = distance
                                //                         routeName = ""
                                //                     }
                                //                     gpxDocument = GPXDocument(text: gpxString)
                                //                     isProcessingGPX = false
                                //                     isFileExporterPresented = true
                                //                 }
                                //             }
                                //         } else {
                                //             locationManager.startRecording()
                                //         }
                                //     }) {
                                //         Label(locationManager.isRecording ? "Stop & Share" : "Record",
                                //               systemImage: locationManager.isRecording ? "stop.circle.fill" : "record.circle")
                                //             .font(.subheadline)
                                //             .fontWeight(.semibold)
                                //             .foregroundColor(.white)
                                //             .frame(maxWidth: .infinity)
                                //             .padding(.vertical, 14)
                                //             .background(locationManager.isRecording ? Color.red : Color.orange)
                                //             .cornerRadius(12)
                                //     }
                                //     .fileExporter(
                                //         isPresented: $isFileExporterPresented,
                                //         document: gpxDocument,
                                //         contentType: UTType(filenameExtension: "gpx") ?? .xml,
                                //         defaultFilename: "MyRun.gpx"
                                //     ) { result in
                                //         if !pendingGPXString.isEmpty {
                                //             // showRouteNamePrompt = true
                                //         }
                                //     }

                                //     // AI Generate Button
                                //     if #available(iOS 26, *) {
                                //         Button(action: { showRouteGenerator = true; runningMenuHeight = .large }) {
                                //             Label("Generate", systemImage: "wand.and.stars")
                                //                 .font(.subheadline)
                                //                 .fontWeight(.semibold)
                                //                 .foregroundColor(.white)
                                //                 .frame(maxWidth: .infinity)
                                //                 .padding(.vertical, 14)
                                //                 .background(Color.purple)
                                //                 .cornerRadius(12)
                                //         }
                                //     }
                                }
                                .padding(.bottom, 30)
                            } // end VStack
                            .padding(.horizontal)
                            } // end ScrollView
                            } // end else (routes/default view)
                            }
                        }
                    }
                    .presentationDetents(runningMenuHeights, selection: $runningMenuHeight)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationCornerRadius(25)
                    .presentationBackground(.ultraThinMaterial) // Glass effect
                    .interactiveDismissDisabled(true)
                    .onChange(of: runningMenuHeight) { newHeight in
                        if (newHeight == .height(100) || newHeight == .height(200) || newHeight == .height(250) || newHeight == .height(350)) {
                            searchWasClicked = false
                        }
                    }
                    .onChange(of: inRunningMode) { newValue in
                        if newValue {
                            if runningMenuHeight == .height(250) { runningMenuHeight = .height(350) }
                            else if runningMenuHeight == .height(100) { runningMenuHeight = .height(200) }
                        } else {
                            if runningMenuHeight == .height(350) { runningMenuHeight = .height(250) }
                            else if runningMenuHeight == .height(200) { runningMenuHeight = .height(100) }
                        }
                    }
                    .alert("Name Your Route", isPresented: $showRouteNamePrompt) {
                        TextField("Route name", text: $routeName)
                        Button("Share") {
                            let sanitized = GPXValidator.sanitizeRouteName(routeName)
                            let name = sanitized.isEmpty ? "My Route" : sanitized
                            uploadService.publishRoute(
                                name: name,
                                gpxString: pendingGPXString,
                                distanceMiles: pendingDistance,
                                coordinates: pendingCoords
                            ) { result in
                                switch result {
                                case .success(_):
                                    AnalyticsService.logRouteShared()
                                case .failure(let error):
                                    alertTitle = "Upload Failed"
                                    alertDetails = error.localizedDescription
                                    showAlert = true
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Give your route a name before sharing it.")
                    }
                    .alert(alertTitle, isPresented: $showAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(alertDetails)
                    }
                    .alert("Run Interrupted", isPresented: $showRecoveryAlert) {
                        Button("Resume Run") {
                            if let snapshot = recoveredSnapshot {
                                resumeInterruptedRun(snapshot)
                            }
                        }
                        Button("Save as Completed") {
                            if let snapshot = recoveredSnapshot {
                                liveRunService.stopSession()
                                liveRunService.cleanupOwnStaleEntries()
                                saveInterruptedRun(snapshot)
                            }
                        }
                        Button("Discard", role: .destructive) {
                            RunPersistenceService.clear()
                            liveRunService.stopSession()
                            liveRunService.cleanupOwnStaleEntries()
                            recoveredSnapshot = nil
                        }
                    } message: {
                        Text("Your last run was interrupted. Would you like to resume or save what you have?")
                    }
                }
            }
            .overlay {
                if isProcessingGPX {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Processing your run...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                }
            }
        }

    func requestHealthKitAccess() {
        healthStore.requestAuthorization{
            success, error in
            if let error = error{
                AppLogger.health.error("Error getting HealthKit authorization: \(error)")
            } else {
                AppLogger.health.info("HealthKit authorization granted")
                self.healthStore.fetchWeeklyDistances { distances in
                    self.healthStore.weeklyDistances = distances
                }
            }
        }
    }

    // MARK: - Run Recovery

    /// Resume an interrupted run in paused state so the user can continue.
    private func resumeInterruptedRun(_ snapshot: RunSnapshot) {
        let locations = snapshot.locations.map { $0.toCLLocation() }

        // Treat time while app was dead as paused time
        let deadTime = Date().timeIntervalSince1970 - snapshot.savedAt

        runSession.runStartDate = Date(timeIntervalSince1970: snapshot.runStartDate)
        runSession.pausedDuration = snapshot.pausedDuration + deadTime
        runSession.isPaused = true
        runSession.isTimerPaused = true
        runSession.pauseStartDate = Date()
        runSession.runData.startTime = Date(timeIntervalSince1970: snapshot.runStartDate)
        runSession.activityType = HKWorkoutActivityType(rawValue: snapshot.activityTypeRawValue) ?? .running
        runSession.currentTimer = snapshot.currentTimer
        runSession.isRunDone = false

        // Restore location state
        locationManager.resumeRunTracking(
            existingLocations: locations,
            existingDistance: snapshot.distance,
            existingElevation: snapshot.elevationGain
        )

        // Start a new workout session for continued background protection
        healthStore.startWorkoutSession(activityType: runSession.activityType)

        // Restore the previously selected route from the snapshot
        if let routeID = snapshot.selectedRouteID {
            selectedRoute = routes.values.flatMap { $0 }.first { $0.id == routeID }
        }

        // Restart multiplayer session if a route is selected
        let routeToResume = selectedRoute
        let converter = routeConverter
        liveRunService.cleanupOwnStaleEntries {
            if let route = routeToResume {
                let routeCoords = converter.convertGPXToRoute(filePath: route.GPXFileURL) ?? []
                liveRunService.startSession(routeID: route.id, sharedRouteID: route.sharedRouteID, routeCoordinates: routeCoords)
            }
        }

        inRunningMode = true
        runningMenuHeight = .height(350)
        recoveredSnapshot = nil

        AnalyticsService.logRunResumed()
        AppLogger.run.info("Resumed interrupted run — \(locations.count) locations, \(String(format: "%.2f", snapshot.distance * 0.000621371)) miles")
    }

    /// Present an interrupted run as completed for the user to save or discard.
    private func saveInterruptedRun(_ snapshot: RunSnapshot) {
        let locations = snapshot.locations.map { $0.toCLLocation() }
        let distanceMiles = snapshot.distance * 0.000621371
        let totalMinutes = snapshot.currentTimer / 60.0
        let minute = Int(snapshot.currentTimer / 60)
        let seconds = String(format: "%02d", Int(snapshot.currentTimer) % 60)

        let activityType = HKWorkoutActivityType(rawValue: snapshot.activityTypeRawValue) ?? .running

        // Calculate pace
        let pace: String
        if activityType == .cycling {
            let hours = totalMinutes / 60.0
            pace = hours > 0 ? String(format: "%.1f", distanceMiles / hours) : "0.0"
        } else {
            if distanceMiles > 0 {
                let minPerMile = totalMinutes / distanceMiles
                let wholeMin = Int(minPerMile)
                let secs = Int((minPerMile - Double(wholeMin)) * 60)
                pace = String(format: "%d:%02d", wholeMin, secs)
            } else {
                pace = "0:00"
            }
        }

        runSession.prevRunDistance = distanceMiles
        runSession.prevRunMinute = minute
        runSession.prevRunSecond = seconds
        runSession.prevRunMinPerMile = pace
        runSession.prevRunElevationGain = snapshot.elevationGain
        runSession.runLocations = locations
        runSession.runData.startTime = Date(timeIntervalSince1970: snapshot.runStartDate)
        runSession.activityType = activityType
        runSession.isRunDone = true

        runningMenuHeight = .height(250)
        recoveredSnapshot = nil

        AppLogger.run.info("Presenting interrupted run for save — \(String(format: "%.2f", distanceMiles)) miles, \(minute):\(seconds)")
    }
    
    private func uploadGPXToFirestore(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Validate file type and size
            try GPXValidator.validateFile(at: url)

            let gpxString = try String(contentsOf: url, encoding: .utf8)

            // Validate content for structure and suspicious patterns
            try GPXValidator.validateContent(gpxString)

            let coords = GPXParser().parse(gpxString: gpxString)

            // Validate coordinates (range, count, and distance)
            try GPXValidator.validateCoordinates(coords)

            let distanceMiles = GPXValidator.calculateDistanceMiles(coords)

            pendingGPXString = gpxString
            pendingCoords = coords
            pendingDistance = distanceMiles
            routeName = url.deletingPathExtension().lastPathComponent
            showRouteNamePrompt = true
            AnalyticsService.logRouteImported()
        } catch let error as GPXValidator.ValidationError {
            alertTitle = "Invalid GPX File"
            alertDetails = error.errorDescription ?? "The file could not be validated."
            showAlert = true
        } catch {
            AppLogger.routes.error("Error reading GPX file: \(error)")
            alertTitle = "Error"
            alertDetails = "Could not read the GPX file."
            showAlert = true
        }
    }

    private func removeRouteFromList(_ route: Route) {
        routes["Run Detroit"]?.removeAll { $0.id == route.id }

        // If the removed route was selected, reset to no route
        if selectedRoute?.id == route.id {
            selectedRoute = nil
        }
    }

    private func removeMyRun(_ route: Route) {
        routes["My Runs"]?.removeAll { $0.id == route.id }

        if selectedRoute?.id == route.id {
            selectedRoute = nil
        }
    }

    // Logic to import the GPX file...
    private func importGPX(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Validate file type and size
            try GPXValidator.validateFile(at: url)

            // Validate content
            let gpxString = try String(contentsOf: url, encoding: .utf8)
            try GPXValidator.validateContent(gpxString)

            // Parse and validate coordinates
            let coords = GPXParser().parse(gpxString: gpxString)
            try GPXValidator.validateCoordinates(coords)

            let filename = url.lastPathComponent
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(filename)

            // Remove existing file if necessary
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: url, to: destinationURL)

            // Generate new ID based on max existing ID
            let maxId = routes["Run Detroit"]?.map { $0.id }.max() ?? 0
            let newId = maxId + 1
            let name = filename.replacingOccurrences(of: ".gpx", with: "")

            let newRoute = Route(
                id: newId,
                name: name,
                GPXFileURL: destinationURL.lastPathComponent,
                color: [0.0, 0.5, 1.0]
            )

            if routes["Run Detroit"] != nil {
                routes["Run Detroit"]?.append(newRoute)
            } else {
                routes["Run Detroit"] = [newRoute]
            }

            selectedRoute = newRoute

        } catch let error as GPXValidator.ValidationError {
            alertTitle = "Invalid GPX File"
            alertDetails = error.errorDescription ?? "The file could not be validated."
            showAlert = true
        } catch {
            AppLogger.routes.error("Error importing GPX: \(error)")
            alertTitle = "Error"
            alertDetails = "Could not import the GPX file."
            showAlert = true
        }
    }
}

#Preview {
    ContentView(loginManager: LoginManager())
}
