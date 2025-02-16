//
//  RunListView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 12/7/24.
//

import SwiftUI

struct RunListView: View {
    @Binding var selectedRun: Pace?
    @Binding var runTypeDict: [Pace: Double]
    
    var body: some View {
        List {
            Picker("Info", selection: $selectedRun) {
                Text("Current Pace").tag(Pace.Current)
                Text("Current Mile Pace").tag(Pace.CurrentMile)
                Text("Average Run Pace").tag(Pace.Average)
            }
        }
    }
}
