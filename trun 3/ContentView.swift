//
//  ContentView.swift
//  trun
//
//  Created by Sabath  Rodriguez on 11/16/24.
//

import SwiftUI
import SwiftData
import MapKit

struct ContentView: View {
    var routeConverter:GPXToRoute = GPXToRoute()
    
    @ObservedObject public var loginManager: LoginManager
    
    @State var runners = [Runner(id: 0, name: "a", iconID: "", location: CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458))]
    
    @State var routes: [String: [Route]] = ["Run Detroit": [
        Route(id: 0, name: "3 mile red", GPXFileURL: "3_miles_red", color: .red),
        Route(id: 1, name: "6 mile red", GPXFileURL: "6_miles_red", color: .red),
        Route(id: 2, name: "10 mile red", GPXFileURL: "10_miles_red", color: .red),
        Route(id: 3, name: "3 mile gold", GPXFileURL: "3_miles_gold", color: .yellow),
        Route(id: 4, name: "6 mile gold", GPXFileURL: "6_miles_gold", color: .yellow),
        Route(id: 5, name: "10 mile gold", GPXFileURL: "10_miles_gold", color: .yellow),
        Route(id: 6, name: "3 mile green", GPXFileURL: "3_miles_green", color: .green),
        Route(id: 7, name: "6 mile green", GPXFileURL: "6_miles_green", color: .green),
        Route(id: 8, name: "10 mile green", GPXFileURL: "10_miles_green", color: .green),
        Route(id: 9, name: "8 mile new", GPXFileURL: "8_miles_new", color: .orange)
    ]]
    
    @State var selectedRoute: Route = Route(id: 0, name: "", GPXFileURL: "", color: .red)
    
    @State var selectedRun: Pace? = .CurrentMile
    
    // this will need to be updated to retrieve actual run values
    @State var runTypeDict: [Pace: Double] = [Pace.Average: 1, Pace.Current: 2, Pace.CurrentMile: 3]
    @State var showSheet: Bool = true
    @State var runningMenuHeight: PresentationDetent = PresentationDetent.height(250)
    @State var searchWasClicked: Bool = false
    
    @StateObject var viewModel: UserLocation = UserLocation()
    
    var runningMenuHeights = Set([PresentationDetent.height(250), PresentationDetent.height(100), PresentationDetent.large])
    
    
    var body: some View {
        
        ZStack {
            // background map
//            Map(coordinateRegion: $viewModel.region, showsUserLocation: true)
            Map(position: $viewModel.regionView) {
                
                UserAnnotation()
                
                MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: selectedRoute.GPXFileURL)!)
                                            .stroke(selectedRoute.color, lineWidth: 2)
//                switch selectedRoute {
//                case Routes.three_red:
////                    MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: routes["Run Detroit"]![0].GPXFileURL) ?? [])
//                    MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_red")!)
//                            .stroke(.red, lineWidth: 2)
//                case Routes.six_red:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_red")!)
//                            .stroke(.red, lineWidth: 2)
//                case Routes.ten_red:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_red")!)
//                            .stroke(.red, lineWidth: 2)
//                case Routes.three_gold:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_gold")!)
//                            .stroke(.yellow, lineWidth: 2)
//                case Routes.six_gold:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_gold")!)
//                            .stroke(.yellow, lineWidth: 2)
//                case Routes.ten_gold:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_gold")!)
//                            .stroke(.yellow, lineWidth: 2)
//                case Routes.three_green:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_green")!)
//                            .stroke(.green, lineWidth: 2)
//                case Routes.six_green:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_green")!)
//                            .stroke(.green, lineWidth: 2)
//                case Routes.ten_green:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_green")!)
//                            .stroke(.green, lineWidth: 2)
//                case Routes.six_red:
//                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "8_miles_new")!)
//                        .stroke(.green, lineWidth: 2)
//                default:
//                    MapPolyline(coordinates: [])
//                }
                
            Annotation("User 2", coordinate: routeConverter.convertGPXToRoute(filePath: selectedRoute.GPXFileURL)![0]) {
                    Circle()
                        .foregroundColor(.blue)
                }
//                
                Annotation("User 3", coordinate: routeConverter.convertGPXToRoute(filePath: "10_miles_green")![4]) {
                    Circle()
                        .foregroundColor(.yellow)
                }
                
                Annotation("User 4", coordinate: routeConverter.convertGPXToRoute(filePath: "10_miles_green")![8]) {
                    Circle()
                        .foregroundColor(.red)
                }
                
                Annotation("User 5", coordinate: routeConverter.convertGPXToRoute(filePath: "10_miles_green")![12]) {
                    Circle()
                        .foregroundColor(.green)
                }
                
                
            }
            .mapControls {
                MapCompass()
            }
            .id(selectedRoute)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                viewModel.checkIfLocationServicesEnabled()
            }
            .onChange(of: selectedRoute) { _ in
                viewModel.centerOnUser()
            }
            .sheet(isPresented: $showSheet) {
                VStack {
                    RunView(selectedRun: $selectedRun, runTypeDict: $runTypeDict, runningMenuHeight: $runningMenuHeight, searchWasClicked: $searchWasClicked, userRegion: viewModel, loginManager: loginManager)
                        .presentationBackgroundInteraction(.enabled)
                        .presentationDetents(runningMenuHeights, selection: $runningMenuHeight)
                        .interactiveDismissDisabled(true)
                        .onChange(of: runningMenuHeight) { newHeight in
                            if (newHeight == .height(100) || newHeight == .height(250)) {
                            searchWasClicked = false
                        }
                    }
                    List {
                        Picker("Run Options", selection: $selectedRoute) {
//                            ForEach(Routes.allCases) { route in
//                                Text(route.rawValue)
//                                    .tag(route)
//                            }
                            var r: [Route] = routes["Run Detroit"]!
                            ForEach(routes["Run Detroit"]!) { route in
                                Text(route.name).tag(route)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .center) {
                Spacer(minLength: 550)
//                    .offset(y: geometry.size.height / 2 + 40)
//                    .border(Color.red, width: 1)
                .frame(height: 100)
                
                Spacer()
            }
            .background(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.black, lineWidth: 1)
            .background(.white)
            .cornerRadius(20)
            .shadow(radius: 80)
            .frame(height: 600)
//                .border(Color.red, width: 1)
//                .offset(y: geometry.size.height / 2 + 50)
            )
        }
    }
}

#Preview {
    ContentView(loginManager: LoginManager())
}
