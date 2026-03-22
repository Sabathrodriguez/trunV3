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
    @State var showSheet: Bool = true
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
    
    var runningMenuHeights = Set([PresentationDetent.height(250), PresentationDetent.height(100), PresentationDetent.large])
    
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
                .sheet(isPresented: $showRouteGenerator) {
                    if #available(iOS 26.0, *) {
                        RouteGeneratorView(
                            routes: $routes,
                            selectedRoute: $selectedRoute,
                            isPresented: $showRouteGenerator,
                            userLocation: viewModel.locationManager?.location?.coordinate
                        )
                    }
                }
                .onAppear {
                    viewModel.checkIfLocationServicesEnabled()
                    profileService.fetchProfileImageURL()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        requestHealthKitAccess()
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
                                    Button(action: {
                                        if locationManager.isRecording {
                                            locationManager.stopRecording()
                                            isProcessingGPX = true

                                            Task {
                                                let gpxString = locationManager.createGPXString()
                                                let coords = GPXParser().parse(gpxString: gpxString)
                                                let distance = locationManager.convertToMiles()

                                                await MainActor.run {
                                                    if !gpxString.isEmpty {
                                                        pendingGPXString = gpxString
                                                        pendingCoords = coords
                                                        pendingDistance = distance
                                                        routeName = ""
                                                    }
                                                    gpxDocument = GPXDocument(text: gpxString)
                                                    isProcessingGPX = false
                                                    isFileExporterPresented = true
                                                }
                                            }
                                        } else {
                                            locationManager.startRecording()
                                        }
                                    }) {
                                        Label(locationManager.isRecording ? "Stop & Share" : "Record",
                                              systemImage: locationManager.isRecording ? "stop.circle.fill" : "record.circle")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(locationManager.isRecording ? Color.red : Color.orange)
                                            .cornerRadius(12)
                                    }

                                    // AI Generate Button
                                    if #available(iOS 26, *) {
                                        Button(action: { showRouteGenerator = true }) {
                                            Label("Generate", systemImage: "wand.and.stars")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .background(Color.purple)
                                                .cornerRadius(12)
                                        }
                                    }
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
                        if (newHeight == .height(100) || newHeight == .height(250)) {
                            searchWasClicked = false
                        }
                    }
                    .fileExporter(
                        isPresented: $isFileExporterPresented,
                        document: gpxDocument,
                        contentType: UTType(filenameExtension: "gpx") ?? .xml,
                        defaultFilename: "MyRun.gpx"
                    ) { result in
                        // After file export completes (saved or cancelled), prompt for route name
                        if !pendingGPXString.isEmpty {
                            // showRouteNamePrompt = true
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
                                    break
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
                print("Error getting health kit data: \(error)")
            } else {
                print("Successfullyretrieved healthkit data")
                self.healthStore.fetchWeeklyDistances { distances in
                    self.healthStore.weeklyDistances = distances
                }
            }
        }
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
        } catch let error as GPXValidator.ValidationError {
            alertTitle = "Invalid GPX File"
            alertDetails = error.errorDescription ?? "The file could not be validated."
            showAlert = true
        } catch {
            print("Error reading GPX file: \(error)")
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
            print("Error importing GPX: \(error)")
            alertTitle = "Error"
            alertDetails = "Could not import the GPX file."
            showAlert = true
        }
    }
}

#Preview {
    ContentView(loginManager: LoginManager())
}
