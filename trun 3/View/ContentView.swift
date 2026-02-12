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
    @State var runners = [
        Runner(id: 0, name: "alan", iconID: "", location: CLLocationCoordinate2D(latitude: 42.34948396682739, longitude: -83.0350112915039), color: .green, routeID: 0),
        Runner(id: 1, name: "sabath", iconID: "", location: CLLocationCoordinate2D(latitude: 42.349634254351, longitude: -83.034625053405), color: .blue, routeID: 1),
        Runner(id: 2, name: "sebas", iconID: "", location: CLLocationCoordinate2D(latitude: 42.3485613707453, longitude: -83.0340027809143), color: .red, routeID: 2),
        Runner(id: 3, name: "Anon", iconID: "", location: CLLocationCoordinate2D(latitude: 42.34982737340033, longitude: -83.03016185760498), color: .orange, routeID: 0)]
    
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
            Map(position: $viewModel.regionView) {
                
                UserAnnotation()
                
                if let coords = routeConverter.convertGPXToRoute(filePath: selectedRoute.GPXFileURL) {
                    MapPolyline(coordinates: coords)
                        .stroke(Color(red: selectedRoute.color[0], green: selectedRoute.color[1], blue: selectedRoute.color[2]), lineWidth: 2)
                }
                
                
                ForEach(runners) { runner in
                    if runner.routeID == selectedRoute.id {
                        Annotation(runner.name, coordinate: runner.location) {
                            Circle()
                                .foregroundColor(runner.color)
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
            }
            .id(selectedRoute)
            .id(runners)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                viewModel.checkIfLocationServicesEnabled()
                requestHealthKitAccess()
            }
            .onChange(of: selectedRoute) { _ in
                viewModel.centerOnUser()
//                position
            }
            .sheet(isPresented: $showSheet) {
                VStack {
                    RunView(selectedRun: $selectedRun,
                            runTypeDict: $runTypeDict,
                            runningMenuHeight: $runningMenuHeight,
                            searchWasClicked: $searchWasClicked,
                            userRegion: viewModel,
                            loginManager: loginManager,
                            healthStore: healthStore,
                            routes: $routes,           // Pass routes binding
                            selectedRoute: $selectedRoute, // Pass selectedRoute binding,
                            showAlert: $showAlert,
                            alertTitle: $alertTitle,
                            alertDetails: $alertDetails
                        )
                        .presentationBackgroundInteraction(.enabled)
                        .presentationDetents(runningMenuHeights, selection: $runningMenuHeight)
                        .interactiveDismissDisabled(true)
                        .onChange(of: runningMenuHeight) { newHeight in
                            if (newHeight == .height(100) || newHeight == .height(250)) {
                            searchWasClicked = false
                        }
                    }
                    if (runningMenuHeight == .large) {
                        List {
                            Picker("Run Options", selection: $selectedRoute) {
                                if let routeList = routes["Run Detroit"] {
                                    ForEach(routeList) { route in
                                        Text(route.name).tag(route)
                                    }
                                }
                            }
                        }
                        
                        Button(action: {
                            isFileImporterPresented = true
                        }) {
                            HStack {                                
                                
                                Image(systemName: "folder.badge.plus")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: iconHeightAndWidth * 0.6, height: iconHeightAndWidth * 0.6) // Slightly smaller icon inside circle
                                    .foregroundColor(Color.gray)
                                    .padding(10)
                                    .overlay(content: {
                                        Circle()
                                            .stroke(.black, lineWidth: 1)
                                            .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                    })
                                    .padding()
                            }
                            .fileImporter(
                                isPresented: $isFileImporterPresented,
                                allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                                allowsMultipleSelection: false
                            ) { result in
                                switch result {
                                case .success(let urls):
                                    if let url = urls.first {
                                        importGPX(from: url)
                                    }
                                case .failure(let error):
                                    print("Error importing file: \(error.localizedDescription)")
                                }
                            }
                            .padding()
                            
                            Button(action: {
                                if locationManager.isRecording {
                                    // STOP RECORDING
                                    locationManager.stopRecording()
                                    // Generate GPX String
                                    let gpxString = locationManager.createGPXString()
                                    // Prepare Document
                                    gpxDocument = GPXDocument(text: gpxString)
                                    // Trigger Export
                                    isFileExporterPresented = true
                                } else {
                                    // START RECORDING
                                    locationManager.startRecording()
                                }
                            }) {
                                Image(systemName: locationManager.isRecording ? "stop.circle.fill" : "mappin.and.ellipse.circle.fill")
                                    .resizable()
                                    .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                    .foregroundColor(locationManager.isRecording ? Color.red : Color.blue)
                                    .overlay(content: {
                                        Circle()
                                        .stroke(.black, lineWidth: 1)
                                })
                                .padding()
                            }
                            // File Exporter Modifier
                            .fileExporter(
                                isPresented: $isFileExporterPresented,
                                document: gpxDocument,
                                contentType: UTType(filenameExtension: "gpx") ?? .xml,
                                defaultFilename: "MyRun.gpx"
                            ) { result in
                                switch result {
                                case .success(let url):
                                    print("Saved to \(url)")
                                    alertTitle = "Success"
                                    alertDetails = "Run saved successfully!"
                                    showAlert = true
                                case .failure(let error):
                                    print("Export failed: \(error.localizedDescription)")
                                    alertTitle = "Error"
                                    alertDetails = "Failed to save file."
                                    showAlert = true
                                }
                            }
                        }
                    }
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
