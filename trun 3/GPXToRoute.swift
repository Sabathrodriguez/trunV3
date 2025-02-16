//
//  GPXToRoute.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/3/25.
//
import MapKit

class GPXToRoute {
    
    func readGPXFile(fileName: String) -> [CLLocationCoordinate2D]? {
        guard let path = Bundle.main.path(forResource: fileName, ofType: "gpx") else {
            print(Bundle.main.bundleURL)
            print("GPX file not found")
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let parser = GPXParser()
            return parser.parseGPX(data: data)
        } catch {
            print("Error reading file: \(error)")
            return nil
        }
    }

    func convertGPXToRoute(filePath: String) -> [CLLocationCoordinate2D]? {
        if let coordinates = readGPXFile(fileName: filePath) {
            print("Parsed \(coordinates.count) coordinates")
            return coordinates
        } else {
            return nil
        }
    }
    
}

