//
//  GPXParser.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/3/25.
//

import MapKit

class GPXParser: NSObject, XMLParserDelegate {
    private var coordinates: [CLLocationCoordinate2D] = []
    private var currentElement = ""
    private var currentLat: Double = 0.0
    private var currentLon: Double = 0.0

    func parseGPX(data: Data) -> [CLLocationCoordinate2D] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return coordinates
    }

    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" {
            currentLat = Double(attributeDict["lat"]!) ?? 0.0
            currentLon = Double(attributeDict["lon"]!) ?? 0.0
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "trkpt" {
            coordinates.append(
                CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
            )
        }
    }
}

