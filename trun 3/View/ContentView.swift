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
    @State var inRunningMode: Bool = false

    let db = Firestore.firestore()
    
    @State var routes: [String: [Route]] = ["Run Detroit": [
        Route(id: 0, name: "3 mile red", GPXFileURL: "3_miles_red", color: [1, 0, 0]),
        Route(id: 1, name: "6 mile red", GPXFileURL: "6_miles_red", color: [1, 0, 0]),
        Route(id: 2, name: "10 mile red", GPXFileURL: "10_miles_red", color: [1, 0, 0]),
        Route(id: 3, name: "3 mile gold", GPXFileURL: "3_miles_gold", color: [1, 1, 0]),
        Route(id: 4, name: "6 mile gold", GPXFileURL: "6_miles_gold", color: [1, 1, 0]),
        Route(id: 5, name: "10 mile gold", GPXFileURL: "10_miles_gold", color: [1, 1, 0]),
        Route(id: 6, name: "3 mile green", GPXFileURL: "3_miles_green", color: [0, 1, 0]),
        Route(id: 7, name: "6 mile green", GPXFileURL: "6_miles_green", color: [0, 1, 0]),
        Route(id: 8, name: "10 mile green", GPXFileURL: "10_miles_green", color: [0, 1, 0]),
        Route(id: 9, name: "8 mile new", GPXFileURL: "8_miles_new", color: [1, 0.647, 0])
    ]]
    
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
    @State private var isUploadImporterPresented = false
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var gpxDocument: GPXDocument?
    
    // We can use the LocationManager from the view model if it's accessible,
    // but the provided UserLocation class seems separate. 
    // Assuming we should use a LocationManager instance here for recording:
    @StateObject var locationManager = LocationManager()
    
    @StateObject var viewModel: UserLocation = UserLocation()
//    @State var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    
    var runningMenuHeights = Set([PresentationDetent.height(250), PresentationDetent.height(100), PresentationDetent.large])
    
    var body: some View {
            ZStack {
                // MAP LAYER
                Map(position: $viewModel.regionView) {
                    UserAnnotation()
                    
                    if let route = selectedRoute,
                       let coords = routeConverter.convertGPXToRoute(filePath: route.GPXFileURL) {
                        MapPolyline(coordinates: coords)
                            .stroke(Color(red: route.color[0], green: route.color[1], blue: route.color[2]), lineWidth: 4)
                    }
                    
                    ForEach(liveRunService.liveRunners) { runner in
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
                    requestHealthKitAccess()
                }
                .onChange(of: selectedRoute) { _ in
                    viewModel.centerOnUser()
                }
                
                // PROFILE MENU OVERLAY
                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: { showDBInspector = true }) {
                                Label("DB Inspector", systemImage: "cylinder.split.1x2")
                            }
                            Button(role: .destructive, action: { loginManager.logout() }) {
                                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                                .padding(.trailing, 16)
                                .padding(.top, 50)
                        }
                    }
                    Spacer()
                }
                .sheet(isPresented: $showDBInspector) {
                    DatabaseInspectorView()
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
                            
//                            // Drag Indicator
//                            Capsule()
//                                .frame(width: 40, height: 4)
//                                .foregroundColor(.gray.opacity(0.5))
//                                .padding(.top, 10)

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
                                routes: $routes,
                                selectedRoute: $selectedRoute,
                                showAlert: $showAlert,
                                alertTitle: $alertTitle,
                                alertDetails: $alertDetails
                            )
                            
                            // ROUTE SELECTION (Visible when expanded)
                            if runningMenuHeight == .large {
                                ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 16) {
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

                                                        // Remove from map (only for non-built-in routes, id >= 10)
                                                        if route.id >= 10 {
                                                            Button(action: {
                                                                removeRouteFromList(route)
                                                            }) {
                                                                Image(systemName: "xmark.circle.fill")
                                                                    .font(.body)
                                                                    .foregroundColor(.secondary)
                                                            }
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

                                // ROUTE LEADERBOARD
                                if let route = selectedRoute {
                                    RouteLeaderboardView(
                                        routeID: route.id,
                                        routeName: route.name,
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
                                HStack(spacing: 12) {
                                    // Import Button (local only)
                                    Button(action: { isFileImporterPresented = true }) {
                                        Label("Import", systemImage: "folder.badge.plus")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(Color.blue)
                                            .cornerRadius(12)
                                    }

                                    // Upload GPX to Firestore
                                    Button(action: { isUploadImporterPresented = true }) {
                                        Label("Upload", systemImage: "icloud.and.arrow.up")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(Color.green)
                                            .cornerRadius(12)
                                    }

                                    // Record/Save Button
                                    Button(action: {
                                        if locationManager.isRecording {
                                            locationManager.stopRecording()
                                            let gpxString = locationManager.createGPXString()
                                            gpxDocument = GPXDocument(text: gpxString)
                                            isFileExporterPresented = true

                                            // Store pending data and prompt for name
                                            if !gpxString.isEmpty {
                                                pendingGPXString = gpxString
                                                pendingCoords = GPXParser().parse(gpxString: gpxString)
                                                pendingDistance = locationManager.convertToMiles()
                                                routeName = ""
                                                showRouteNamePrompt = true
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
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(locationManager.isRecording ? Color.red : Color.orange)
                                            .cornerRadius(12)
                                    }
                                }
                                .padding(.bottom, 30)
                            } // end VStack
                            .padding(.horizontal)
                            } // end ScrollView
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
                    // ... [Keep file importer/exporter modifiers] ...
                    .fileImporter(
                        isPresented: $isFileImporterPresented,
                        allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            importGPX(from: url)
                        }
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
                    .fileExporter(
                        isPresented: $isFileExporterPresented,
                        document: gpxDocument,
                        contentType: UTType(filenameExtension: "gpx") ?? .xml,
                        defaultFilename: "MyRun.gpx"
                    ) { result in
                         // handle result
                    }
                    .alert("Name Your Route", isPresented: $showRouteNamePrompt) {
                        TextField("Route name", text: $routeName)
                        Button("Share") {
                            let name = routeName.trimmingCharacters(in: .whitespaces)
                            SharedRouteService().publishRoute(
                                name: name.isEmpty ? "My Route" : name,
                                gpxString: pendingGPXString,
                                distanceMiles: pendingDistance,
                                coordinates: pendingCoords
                            )
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Give your route a name before sharing it.")
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
            }
        }
    }
    
    private func getRouteData() {
        // ... existing code ...
    }
    
    private func uploadGPXToFirestore(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let gpxString = try String(contentsOf: url, encoding: .utf8)
            let coords = GPXParser().parse(gpxString: gpxString)

            guard !coords.isEmpty else {
                alertTitle = "Invalid File"
                alertDetails = "The GPX file contains no track points."
                showAlert = true
                return
            }

            // Calculate distance from coordinates
            var totalMeters: Double = 0
            for i in 1..<coords.count {
                let prev = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                totalMeters += curr.distance(from: prev)
            }
            let distanceMiles = totalMeters * 0.000621371

            pendingGPXString = gpxString
            pendingCoords = coords
            pendingDistance = distanceMiles
            routeName = url.deletingPathExtension().lastPathComponent
            showRouteNamePrompt = true
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

    // Logic to import the GPX file...
    private func importGPX(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
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
                GPXFileURL: destinationURL.path,
                color: [0.0, 0.5, 1.0]
            )
            
            if routes["Run Detroit"] != nil {
                routes["Run Detroit"]?.append(newRoute)
            } else {
                routes["Run Detroit"] = [newRoute]
            }
            
            selectedRoute = newRoute
            
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
