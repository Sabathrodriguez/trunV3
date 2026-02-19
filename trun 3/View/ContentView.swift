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
    
    @State var selectedRoute: Route = Route(id: 0, name: "", GPXFileURL: "3_miles_red", color: [1, 0, 0])
    
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
                    
                    if let coords = routeConverter.convertGPXToRoute(filePath: selectedRoute.GPXFileURL) {
                        MapPolyline(coordinates: coords)
                            .stroke(Color(red: selectedRoute.color[0], green: selectedRoute.color[1], blue: selectedRoute.color[2]), lineWidth: 4) // Thicker line
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
                            
                            // ROUTE SELECTION CAROUSEL (Visible when expanded)
                            if runningMenuHeight == .large {
                                VStack(alignment: .leading) {
//                                    Text("Select Route")
//                                        .font(.headline)
//                                        .padding(.horizontal)
                                    
//                                    ScrollView(.horizontal, showsIndicators: false) {
//                                        HStack(spacing: 15) {
//                                            if let routeList = routes["Run Detroit"] {
//                                                ForEach(routeList) { route in
//                                                    Button(action: {
//                                                        selectedRoute = route
//                                                    }) {
//                                                        VStack(alignment: .leading) {
//                                                            Text(route.name)
//                                                                .font(.system(size: 16, weight: .bold))
//                                                                .foregroundColor(.primary)
//                                                            Text("\(route.GPXFileURL)") // Or distance if available
//                                                                .font(.caption)
//                                                                .foregroundColor(.secondary)
//                                                        }
//                                                        .padding()
//                                                        .frame(width: 160, height: 80)
//                                                        .background(
//                                                            RoundedRectangle(cornerRadius: 16)
//                                                                .fill(Color(UIColor.secondarySystemBackground))
//                                                                .shadow(color: selectedRoute.id == route.id ? Color.blue.opacity(0.4) : Color.clear, radius: 8)
//                                                                .overlay(
//                                                                    RoundedRectangle(cornerRadius: 16)
//                                                                        .stroke(selectedRoute.id == route.id ? Color.blue : Color.clear, lineWidth: 2)
//                                                                )
//                                                        )
//                                                    }
//                                                }
//                                            }
//                                        }
//                                        .padding(.horizontal)
//                                    }
                                }
                                .padding(.bottom)

                                // ROUTE LEADERBOARD
                                RouteLeaderboardView(
                                    routeID: selectedRoute.id,
                                    routeName: selectedRoute.name,
                                    liveRunners: liveRunService.liveRunners,
                                    isRunning: inRunningMode
                                )
                                .padding(.horizontal)

                                // SHARED ROUTE LIBRARY
                                SharedRouteLibraryView(
                                    userLocation: viewModel,
                                    routes: $routes,
                                    selectedRoute: $selectedRoute
                                )
                                .padding(.horizontal)

                                // IMPORT / EXPORT / SHARE CONTROLS
                                HStack(spacing: 12) {
                                    // Import Button
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

                                    // Record/Save Button
                                    Button(action: {
                                        if locationManager.isRecording {
                                            locationManager.stopRecording()
                                            let gpxString = locationManager.createGPXString()
                                            gpxDocument = GPXDocument(text: gpxString)
                                            isFileExporterPresented = true

                                            // Share to the community
                                            if !gpxString.isEmpty {
                                                let coords = GPXParser().parse(gpxString: gpxString)
                                                SharedRouteService().publishRoute(
                                                    name: "My Route",
                                                    gpxString: gpxString,
                                                    distanceMiles: locationManager.convertToMiles(),
                                                    coordinates: coords
                                                )
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
                    .fileExporter(
                        isPresented: $isFileExporterPresented,
                        document: gpxDocument,
                        contentType: UTType(filenameExtension: "gpx") ?? .xml,
                        defaultFilename: "MyRun.gpx"
                    ) { result in
                         // handle result
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
