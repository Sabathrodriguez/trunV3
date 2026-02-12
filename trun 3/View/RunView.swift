//
//  RunView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/7/24.
//

import SwiftUI
import MapKit

struct RunView: View {
    @Binding var selectedRun: Pace?
    @Binding var runTypeDict: [Pace: Double]
    @Binding var runningMenuHeight: PresentationDetent
    @Binding var searchWasClicked: Bool
    
    @ObservedObject var userRegion: UserLocation
    @State var inRunningMode: Bool = false
    @ObservedObject var loginManager: LoginManager
    
//    @Binding var cameraPosition: MapCameraPosition
    
    @ObservedObject var healthStore: HealthStore
    
    @Binding var routes: [String: [Route]]
    
    @Binding var selectedRoute: Route
    
    @Binding var showAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertDetails: String
    
    @State var runData: Run = Run(time: 0, distance: 0, averagePace: "", caloriesBurned: 0, dateString: "", startTime: Date())
    @State var currentDate: Date = Date()
    
    
    var body: some View {
        VStack {
            // running info
            RunInfoView(runData: runData, currentDate: currentDate, loginManager: loginManager, healthStore: healthStore, selectedRun: $selectedRun, runTypeDict: $runTypeDict, runningMenuHeight: $runningMenuHeight, searchWasClicked: $searchWasClicked, inRunningMode: $inRunningMode, region: userRegion, routes: $routes, selectedRoute: $selectedRoute, showAlert: $showAlert, alertTitle: $alertTitle, alertDetails: $alertDetails)
            
            // this allows the user to select what to display as far as running information
            if (runningMenuHeight == .large && inRunningMode) {
                RunListView(selectedRun: $selectedRun, runTypeDict: $runTypeDict)
            } else {
                Spacer()
            }
        }
    }
}
