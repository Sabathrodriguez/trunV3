//
//  RouteAnnotationHelpers.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 2/23/26.
//

import CoreLocation
import SwiftUI

struct DirectionalArrow: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
}

struct RainbowSegment: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

enum RouteAnnotationHelpers {

    /// Split route coordinates into segments, each with a rainbow color.
    static func rainbowSegments(from coords: [CLLocationCoordinate2D], segmentCount: Int = 30) -> [RainbowSegment] {
        guard coords.count >= 2 else { return [] }

        let rainbowColors: [Color] = (0..<segmentCount).map { i in
            Color(hue: Double(i) / Double(segmentCount), saturation: 0.9, brightness: 0.95)
        }

        let pointsPerSegment = max(2, coords.count / segmentCount)
        var segments: [RainbowSegment] = []

        for i in 0..<segmentCount {
            let startIdx = i * pointsPerSegment
            let endIdx = (i == segmentCount - 1) ? coords.count : min((i + 1) * pointsPerSegment + 1, coords.count)
            guard startIdx < coords.count && endIdx > startIdx else { continue }

            let slice = Array(coords[startIdx..<endIdx])
            if slice.count >= 2 {
                segments.append(RainbowSegment(coordinates: slice, color: rainbowColors[i]))
            }
        }

        return segments
    }

    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Generate arrows every `intervalMiles` (default 0.1 mi), including one at the start.
    static func generateArrows(from coords: [CLLocationCoordinate2D], intervalMiles: Double = 0.1) -> [DirectionalArrow] {
        guard coords.count >= 2 else { return [] }

        let intervalMeters = intervalMiles * 1609.34
        var arrows: [DirectionalArrow] = []

        // Arrow at the beginning
        let startBearing = bearing(from: coords[0], to: coords[1])
        arrows.append(DirectionalArrow(coordinate: coords[0], bearing: startBearing))

        var distanceSinceLastArrow: Double = 0

        for i in 1..<coords.count {
            let prev = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            distanceSinceLastArrow += curr.distance(from: prev)

            if distanceSinceLastArrow >= intervalMeters && i < coords.count - 1 {
                let b = bearing(from: coords[i], to: coords[i + 1])
                arrows.append(DirectionalArrow(coordinate: coords[i], bearing: b))
                distanceSinceLastArrow = 0
            }
        }

        return arrows
    }
}
