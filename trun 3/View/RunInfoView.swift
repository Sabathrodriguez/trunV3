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
import FirebaseAuth
import FirebaseFirestore
import UniformTypeIdentifiers

struct RunInfoView: View {
    let db = Firestore.firestore()
    
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
    
    @Binding var routes: [String: [Route]]
    @Binding var selectedRoute: Route
    
    @State var isPaused: Bool = false
    @State var searchField: String = ""
    
    @StateObject var locationManager = LocationManager()
    
    @FocusState var isSearchFieldFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var currentTimer = 0.0
    @State private var isTimerPaused: Bool = false
    
    let generator = UISelectionFeedbackGenerator()
    private let cancelTimer = 1.5
    
    @State private var isCameraAvailable = false
    @State private var isImagePickerPresented = false
    
    @State var isRunDone: Bool = false
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
                    Text("Great Run!")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundColor(.primary)
                    
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
                            Text("Save Run")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 5)
                        }
                    }
                }
                .padding(.horizontal)
                
            // --- STATE 2: IDLE (Pre-Run) ---
            } else if !inRunningMode {
                HStack {
                    // Search Button
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
                }
                .padding(.bottom, 20)
            }
        }
        .padding()
        .onReceive(timer) { _ in
            if !isTimerPaused {
                currentTimer += 0.1
                // Simple pace calc for display update every 3 seconds
                 if Int(currentTimer) % 3 == 0 {
                    prevRunMinPerMile = calculateMilesPerMinute(distance: locationManager.convertToMiles(), time: currentTimer / 60)
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
    }
    
    func saveRunAction() {
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
    
    private func clearRunInformation() {
        prevRunMinute = 0
        prevRunSecond = ""
        prevRunDistance = 0
        isRunDone = false
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
        let ref = try? await db.collection("users")
        
        do {
            let jsonData = try JSONEncoder().encode(runData)
            let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
            if let dict = json as? [String: Any], let ref = ref {
                if let currentUser = Auth.auth().currentUser {
                    try await ref.document(currentUser.uid).collection("runData").addDocument(data: dict)
                }
            }
            clearRunInformation()
            showAlert = true
            alertTitle = "Success"
            alertDetails = "Run saved to your account!"
        } catch {
            print("Error encoding data: \(error)")
        }
    }
}
