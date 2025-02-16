//
//  RunView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/7/24.
//

import SwiftUI

struct RunView: View {
    @Binding var selectedRun: Pace?
    @Binding var runTypeDict: [Pace: Double]
    @Binding var runningMenuHeight: PresentationDetent
    @Binding var searchWasClicked: Bool
    @ObservedObject var userRegion: UserLocation
    @State var inRunningMode: Bool = false
    @ObservedObject var loginManager: LoginManager
    @State var runData: RunData = RunData(time: 0, distance: 0, averagePace: "", caloriesBurned: 0, dateString: "")
    @State var currentDate: Date = Date()
    
    
    var body: some View {
        VStack {
            // running info
            RunInfoView(runData: runData, currentDate: currentDate, loginManager: loginManager, selectedRun: $selectedRun, runTypeDict: $runTypeDict, runningMenuHeight: $runningMenuHeight, searchWasClicked: $searchWasClicked, inRunningMode: $inRunningMode, region: userRegion)
            
            // this allows the user to select what to display as far as running information
            if (runningMenuHeight == .large && inRunningMode) {
                RunListView(selectedRun: $selectedRun, runTypeDict: $runTypeDict)
            } else {
                Spacer()
            }
        }
    }
}
