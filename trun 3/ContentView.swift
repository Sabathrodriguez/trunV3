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
    
    @State var selectedRun: Pace? = .CurrentMile
    @State var selectedRoute: Routes = Routes.three_red
    @State var selectedRouteOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8]
    
    // this will need to be updated to retrieve actual run values
    @State var runTypeDict: [Pace: Double] = [Pace.Average: 1, Pace.Current: 2, Pace.CurrentMile: 3]
    @State var showSheet: Bool = true
    @State var runningMenuHeight: PresentationDetent = PresentationDetent.height(250)
    @State var searchWasClicked: Bool = false
    
    @StateObject var viewModel: UserLocation = UserLocation()
    
    var runningMenuHeights = Set([PresentationDetent.height(250), PresentationDetent.height(100), PresentationDetent.large])
    
    @State var routeCoordinates = [
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF
        CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), // LA
        CLLocationCoordinate2D(latitude: 40.76078, longitude: -111.89105) // SLC
    ]
    
    @State var routes: [Route] = [Route(id: 2, name: "3 mile red", GPXFileURL: "3_mile_red"),
                                  Route(id: 3, name: "6 mile red", GPXFileURL: "6_mile_red"),
                                  Route(id: 4, name: "10 mile red", GPXFileURL: "10_mile_red"),
                                  Route(id: 5, name: "3 mile gold", GPXFileURL: "3_mile_gold"),
                                  Route(id: 6, name: "6 mile gold", GPXFileURL: "6_mile_gold"),
                                  Route(id: 7, name: "10 mile gold", GPXFileURL: "10_mile_gold"),
                                  Route(id: 8, name: "3 mile green", GPXFileURL: "3_mile_green"),
                                  Route(id: 9, name: "6 mile green", GPXFileURL: "6_mile_green"),
                                  Route(id: 10, name: "10 mile green", GPXFileURL: "10_mile_green")]
    
    
    var body: some View {
        ZStack {
            // background map
//            Map(coordinateRegion: $viewModel.region, showsUserLocation: true)
            Map(position: $viewModel.regionView) {
                
                UserAnnotation()
                
                switch selectedRoute {
                case .three_red:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_red")!)
                            .stroke(.red, lineWidth: 2)
                case .six_red:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_red")!)
                            .stroke(.red, lineWidth: 2)
                case .ten_red:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_red")!)
                            .stroke(.red, lineWidth: 2)
                case .three_gold:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_gold")!)
                            .stroke(.yellow, lineWidth: 2)
                case .six_gold:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_gold")!)
                            .stroke(.yellow, lineWidth: 2)
                case .ten_gold:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_gold")!)
                            .stroke(.yellow, lineWidth: 2)
                case .three_green:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "3_miles_green")!)
                            .stroke(.green, lineWidth: 2)
                case .six_green:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "6_miles_green")!)
                            .stroke(.green, lineWidth: 2)
                case .ten_green:
                        MapPolyline(coordinates: routeConverter.convertGPXToRoute(filePath: "10_miles_green")!)
                            .stroke(.green, lineWidth: 2)
                }
                
                Annotation("User 2", coordinate: routeConverter.convertGPXToRoute(filePath: "10_miles_green")![0]) {
                    Circle()
                        .foregroundColor(.blue)
                }
                
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
                            ForEach(Routes.allCases) { route in
                                Text(route.rawValue)
                                    .tag(route)
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
