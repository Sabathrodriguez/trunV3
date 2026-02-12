//
//  GPXToRoute.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/3/25.
//
import MapKit

class GPXToRoute {
    
    func readGPXFile(fileName: String) -> [CLLocationCoordinate2D]? {
        // 1. Check if the string is a valid file path on the filesystem (for imported files)
        if FileManager.default.fileExists(atPath: fileName) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: fileName))
                let parser = GPXParser()
                return parser.parseGPX(data: data)
            } catch {
                print("Error reading external file: \(error)")
            }
        }
        
        // 2. Fallback to Bundle resource (for default assets)
        if let path = Bundle.main.path(forResource: fileName, ofType: "gpx") {
             do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let parser = GPXParser()
                return parser.parseGPX(data: data)
            } catch {
                print("Error reading bundle file: \(error)")
                return nil
            }
        }
        
        print("GPX file not found: \(fileName)")
        return nil
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
