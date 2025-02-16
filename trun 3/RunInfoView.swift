//
//  RunInfoView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/7/24.
//

import SwiftUI
import SwiftData
import MapKit
import AVFoundation
import UIKit
import Photos
import FirebaseAuth
import FirebaseFirestore

struct RunInfoView: View {
    let db = Firestore.firestore()
    
    @State var runData: RunData
    @State var currentDate: Date
    
    @ObservedObject var loginManager: LoginManager
    @Binding var selectedRun: Pace?
    @Binding var runTypeDict: [Pace: Double]
    @Binding var runningMenuHeight: PresentationDetent
    @Binding var searchWasClicked: Bool
    @Binding var inRunningMode: Bool
    
    @State var isPaused: Bool = false
    @State private var isLongPressing = false
    @State var searchField: String = ""
    
    @StateObject var locationManager = LocationManager()
    
    @FocusState var isSearchFieldFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var region: UserLocation
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect() // 1-second interval
    @State private var currentTimer = 0.0
    @State private var isTimerPaused: Bool = false
    
    var iconHeightAndWidth: CGFloat = 75
    
    let generator = UISelectionFeedbackGenerator()
    
    private let cancelTimer = 1.5
    
    @State private var isCameraAvailable = false
    @State private var isImagePickerPresented = false
    
    @State var isRunDone: Bool = false
    var minRunDistance: Double = 3
    
    @State var prevRunDistance: Double = 0
    @State var prevRunMinute: Int = 0
    @State var prevRunSecond: String = ""
    
    @State var showAlert: Bool = false
    @State var alertTitle: String = ""
    @State var alertDetails: String = ""

    var prevRunMinPerMile: String = ""
            
    var body: some View {
        
        let twoDecimalPlaceRun = String(format: "%.2f", locationManager.convertToMiles())
        let twoDecimalPlaceRunArray = twoDecimalPlaceRun.split(separator: ".")
        let minute = Int(currentTimer/60)
        let seconds = String(format: "%.1f", currentTimer.truncatingRemainder(dividingBy: 60.0))
        let minPerMile = String(format: "%.2f", locationManager.convertToMiles() > 0 ? Double(minute)/locationManager.convertToMiles() : 0)
        
        HStack {
            if (isRunDone) {
                VStack(alignment: .leading) {
                    let formattedPrevDistance = String(format: "Distance: %.2f", prevRunDistance)
                    Text(formattedPrevDistance)
                    let formattedPrevTime = "Time: \(prevRunMinute) min. \(prevRunSecond) sec."
                    Text(formattedPrevTime)
                    
                    HStack {
                        Button(action: {
                            currentDate = Date()
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .medium
                            dateFormatter.timeStyle = .short
                            runData.averagePace = prevRunMinPerMile
                            runData.distance = prevRunDistance
                            runData.time = Double(prevRunMinute) + Double(prevRunSecond)!/60
                            runData.dateString = dateFormatter.string(from: currentDate)
                            Task {
                                await uploadUserRun()
                            }
                        })
                        {
                            Circle()
                                .frame(width: 120, height: 100)
                                .foregroundColor(Color.green)
                                .overlay(content: {
                                    Circle()
                                        .stroke(Color(.black), lineWidth: 2)
                                })
                                .overlay {
                                    Text("Save")
                                        .foregroundColor(Color.black)
                                        .fontWeight(.bold)
                                        .font(.title2)
                                        .foregroundColor(Color.black)
                                }
                        }
                        
                        Button(action: {
                          clearRunInformation()
                        })
                        {
                            Circle()
                                .frame(width: 120, height: 100)
                                .foregroundColor(Color.red)
                                .overlay(content: {
                                    Circle()
                                        .stroke(Color(.black), lineWidth: 2)
                                    
                                })
                                .overlay {
                                    Text("Delete")
                                        .foregroundColor(Color.black)
                                        .fontWeight(.bold)
                                        .font(.title2)
                                }
                        }
                    }
                }
                .padding()
                .font(.title2)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .bold()
                               
                
            } else if (runningMenuHeight == .height(100)) {
                if (!inRunningMode) {
                    VStack {
                        Spacer()
                        Button(action: {
                            inRunningMode = true
                            locationManager.distance = 0
                            locationManager.startTracking()
                            isTimerPaused = false
                            isPaused = false
                            currentTimer = 0
                        }) {
                            Rectangle()
                                .frame(width: 120, height: 70)
                                .foregroundColor(Color.green)
                                .cornerRadius(10)
                                .overlay(content: {
                                    Rectangle()
                                        .stroke(.black, lineWidth: 2)
                                })
                                .overlay {
                                    Text("GO")
                                        .foregroundColor(Color.black)
                                        .fontWeight(.bold)
                                        .font(.title)
                                }
                        }
                    }
                } else {
                    if (selectedRun != nil) {
                        Text("Distance: \(twoDecimalPlaceRunArray[0]).\(twoDecimalPlaceRunArray[1]) mi")
                            .font(.title2)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .bold()
                            .padding(.top, 30)
                    } else {
                        Text("Select a run type")
                            .padding(.top, 30)
                    }
                }
            } else if (searchWasClicked && runningMenuHeight == .large) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .padding(Edge.Set([.leading]))
                    
                    TextField("Search", text: $searchField)
                        .multilineTextAlignment(.leading)
                        .focused($isSearchFieldFocused)
                }
                .frame(height: 40)
                .background(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray6))
                .cornerRadius(20)
                .padding(Edge.Set([.top, .leading, .bottom]))
                
                Button("Cancel", action: {
                    searchWasClicked = false
                    runningMenuHeight = .height(250)
                })
                .padding(Edge.Set([.trailing]))
            } else {
                if (!inRunningMode) {
                    VStack {
                        HStack {
                            // button will allow user to search location
                            Button(action: {
                                runningMenuHeight = .large
                                searchWasClicked = true
                                isSearchFieldFocused = true
                            })
                            {
                                Image(systemName: "magnifyingglass.circle.fill")
                                    .resizable()
                                    .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                    .foregroundColor(Color.gray)
                                    .overlay(content: {
                                        Circle()
                                            .stroke(.black, lineWidth: 1)
                                    })
                                    .padding()
                            }
                            
                            Spacer()
                            
                            VStack {
                                Button(action: {
                                    inRunningMode = true
                                    locationManager.distance = 0
                                    locationManager.startTracking()
                                    isTimerPaused = false
                                    isPaused = false
                                    currentTimer = 0
                                    isRunDone = false
                                }) {
                                    Circle()
                                        .frame(width: 120, height: 120)
                                        .foregroundColor(Color.green)
                                        .overlay(content: {
                                            Circle()
                                                .stroke(Color(.black), lineWidth: 2)
                                        })
                                        .overlay {
                                            Text("GO")
                                                .foregroundColor(Color.black)
                                                .fontWeight(.bold)
                                                .font(.title)
                                        }
                                        .padding()
                                }
                            }
                            
                            Spacer()
                            
                            // this will locate the user based on the phone gps
                            Button(action: {
                                region.checkLocationAuthorization()
                            }) {
                                Image(systemName: "location.circle.fill")
                                    .resizable()
                                    .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                    .foregroundColor(Color.blue)
                                    .overlay(content: {
                                        Circle()
                                            .stroke(.black, lineWidth: 1)
                                    })
                                    .padding()
                                //                                            .border(Color.blue, width: 1)
                            }
                        }
                        Button(action: {
                            loginManager.isLoggedIn = false
                        }) {
                            Text("Sign Out")
                        }
                    }
                } else {
                    VStack {

                        if (selectedRun != nil) {

                            VStack(alignment: .leading) {
                                Text("Distance: \(twoDecimalPlaceRunArray[0]).\(twoDecimalPlaceRunArray[1]) mi")
                                Text("Time: \(minute):\(seconds)")
                                Text("min/mile: \(minPerMile)")
                            }
                            .font(.title2)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .bold()
                            .padding(.top, 30)
                        } else {
                            Text("Select a run type")
                            .padding()
                        }
                        HStack {

                        // button will allow user to search location
                        Button(action: {
                            isImagePickerPresented = true
                        })
                        {
                            Image(systemName: "camera.circle.fill")
                                .resizable()
                                .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                .foregroundColor(Color.gray)
                                .overlay(content: {
                                    Circle()
                                        .stroke(.black, lineWidth: 1)
                                })
                                .padding()
                        }
                        .disabled(!isCameraAvailable)
                        .onAppear(perform: checkCameraAvailability)
                        .sheet(isPresented: $isImagePickerPresented) {
                            ImagePicker(sourceType: .camera) { image in
                                // Handle the captured image here (optional)
                                if let image = image {
                                    saveImageToPhotoLibrary(image: image)
                                }
                            }
                        }                        

                        Spacer()

                        VStack {
                            if (isPaused) {
                                Button(action: {}){
                                    Circle()
                                    .frame(width: 120, height: 120)
                                    .foregroundColor(Color.orange)
                                    .overlay(content: {
                                        Circle()
                                            .stroke(.black, lineWidth: 2)
                                    })
                                    .overlay {
                                        Text("Paused")
                                            .foregroundColor(Color.black)
                                            .fontWeight(.bold)
                                            .font(.title)
                                    }
                                    .padding()
                                }
                                .simultaneousGesture(LongPressGesture(minimumDuration: cancelTimer).onEnded { _ in
                                    prevRunMinute = minute
                                    prevRunSecond = seconds
                                    prevRunDistance = locationManager.convertToMiles()
                                    inRunningMode = false
                                    locationManager.stopTracking()
                                    isTimerPaused = true
                                    currentTimer = 0
                                    generator.prepare()
                                    generator.selectionChanged()
//                                    if (locationManager.distance > minRunDistance) {
                                        isRunDone = true
//                                    }
                                })
                                .simultaneousGesture(TapGesture().onEnded {
                                    isPaused = false
                                    locationManager.startTracking()
                                    isTimerPaused = false
                                })
                            } else {
                                Button(action: {}) {
                                    Circle()
                                    .frame(width: 120, height: 120)
                                    .foregroundColor(Color.yellow)
                                    .overlay(content: {
                                        Circle()
                                            .stroke(.black, lineWidth: 2)
                                    })
                                    .overlay {
                                        Text("Pause")
                                            .foregroundColor(Color.black)
                                            .fontWeight(.bold)
                                            .font(.title)
                                    }
                                    .padding()
                            }
                                .simultaneousGesture(LongPressGesture(minimumDuration: cancelTimer).onEnded { _ in
                                prevRunMinute = minute
                                prevRunSecond = seconds
                                prevRunDistance = locationManager.convertToMiles()
                                inRunningMode = false
                                locationManager.stopTracking()
                                isTimerPaused = true
                                currentTimer = 0
                                generator.prepare()
                                generator.selectionChanged()
//                                if (locationManager.distance > minRunDistance) {
                                    isRunDone = true
//                                }
                            })
                            .simultaneousGesture(TapGesture().onEnded {
                                isPaused = true
                                locationManager.pauseTracking()
                                isTimerPaused = true
                            })
                            }
                        }
                        Spacer()

                        // this will locate the user based on the phone gps
                        Button(action: {
                            print("location clicked")
                            region.checkLocationAuthorization()
                        }) {
                            Image(systemName: "location.circle.fill")
                                .resizable()
                                .frame(width: iconHeightAndWidth, height: iconHeightAndWidth)
                                .foregroundColor(Color.blue)
                                .overlay(content: {
                                    Circle()
                                        .stroke(.black, lineWidth: 1)
                                })
                                .padding()
                            }
                        }
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            if (!isTimerPaused) {
                currentTimer += 0.1
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertDetails), dismissButton: .default(Text("OK")))
        }
        .onAppear(perform: checkCameraAvailability)
    }
    
    private func checkCameraAvailability() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.isCameraAvailable = granted
            }
        }
    }
    
    private func saveImageToPhotoLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }
    
    private func clearRunInformation() {
        prevRunMinute = 0
        prevRunSecond = ""
        prevRunDistance = 0
        generator.prepare()
        generator.selectionChanged()
//                                    if (locationManager.distance > minRunDistance) {
        isRunDone = false
    }
    
    private func uploadUserRun() async {
//        let ref = Database.database().reference()
        let ref = try await db.collection("users")
//        let userRef = ref.child("users").child(Auth.auth().currentUser?.uid ?? "Unknown")
        
        do {
            let jsonData = try JSONEncoder().encode(runData)
//            let jsonString = String(data: jsonData, encoding: .utf8)
//            ref.addDocument(data: jsonString)
            let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
            if let dict = json as? [String: Any] {
                if let currentUser = Auth.auth().currentUser {
                    try await ref.document(currentUser.uid).collection("runData").addDocument(data: dict)
//                    try await ref.document(currentUser.uid).setData(dict)
//                    try await ref.document(currentUser.uid).setData(dict)
                }
            }
            clearRunInformation()
            showAlert = true
            alertTitle = "Run being saved to your account!"
            alertDetails = "Run is being saved to your account. You can view your runs in the 'My Runs' tab."
        } catch {
            print("Error encoding data: \(error)")
        }
    }
}
