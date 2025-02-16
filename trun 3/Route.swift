//
//  Route.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/11/25.
//

class Route {
    var id: Double
    var runners: [Runner]?
    var name: String
    var GPXFileURL: String?
    
    init(id: Double = 0, runners: [Runner] = [], name: String = "", GPXFileURL: String? = nil) {
        self.id = id
        self.runners = runners
        self.name = name
        self.GPXFileURL = GPXFileURL
    }
}
