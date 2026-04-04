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
                AppLogger.routes.error("Error reading external GPX file: \(error)")
            }
        }

        // 2. Try resolving the filename in the app's Documents directory
        //    (handles cases where only a filename or a stale absolute path was stored)
        let justFilename = (fileName as NSString).lastPathComponent
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentsPath = documentsURL.appendingPathComponent(justFilename).path
        if documentsPath != fileName, FileManager.default.fileExists(atPath: documentsPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: documentsPath))
                let parser = GPXParser()
                return parser.parseGPX(data: data)
            } catch {
                AppLogger.routes.error("Error reading GPX from Documents: \(error)")
            }
        }

        // 3. Fallback to Bundle resource (for default assets)
        if let path = Bundle.main.path(forResource: fileName, ofType: "gpx") {
             do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let parser = GPXParser()
                return parser.parseGPX(data: data)
            } catch {
                AppLogger.routes.error("Error reading GPX from bundle: \(error)")
                return nil
            }
        }

        AppLogger.routes.error("GPX file not found: \(fileName)")
        return nil
    }

    func convertGPXToRoute(filePath: String) -> [CLLocationCoordinate2D]? {
        if let coordinates = readGPXFile(fileName: filePath) {
            AppLogger.routes.debug("Parsed \(coordinates.count) GPX coordinates")
            return coordinates
        } else {
            return nil
        }
    }
    
}
