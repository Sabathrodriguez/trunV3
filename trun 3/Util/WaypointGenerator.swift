import CoreLocation

@available(iOS 26.0, *)
class WaypointGenerator {

    /// Generate waypoints for a route based on parsed parameters and user's current location.
    func generateWaypoints(
        from startLocation: CLLocationCoordinate2D,
        request: RouteRequest,
        directionBiasCoordinate: CLLocationCoordinate2D? = nil
    ) -> [CLLocationCoordinate2D] {
        switch request.routeType {
        case .loop:
            return generateLoopWaypoints(
                start: startLocation,
                targetDistanceMiles: request.targetDistanceMiles,
                biasToward: directionBiasCoordinate
            )
        case .outAndBack:
            return generateOutAndBackWaypoints(
                start: startLocation,
                targetDistanceMiles: request.targetDistanceMiles,
                biasToward: directionBiasCoordinate
            )
        case .pointToPoint:
            if let destination = directionBiasCoordinate {
                return [startLocation, destination]
            }
            return generateOutAndBackWaypoints(
                start: startLocation,
                targetDistanceMiles: request.targetDistanceMiles,
                biasToward: nil
            )
        }
    }

    // MARK: - Loop Generation

    private func generateLoopWaypoints(
        start: CLLocationCoordinate2D,
        targetDistanceMiles: Double,
        biasToward: CLLocationCoordinate2D?,
        waypointCount: Int = 5
    ) -> [CLLocationCoordinate2D] {
        let radiusMiles = targetDistanceMiles / (2.0 * .pi)
        let radiusDegrees = radiusMiles * 0.0145

        let biasAngle: Double
        if let bias = biasToward {
            biasAngle = bearing(from: start, to: bias)
        } else {
            biasAngle = Double.random(in: 0..<(2.0 * .pi))
        }

        var waypoints: [CLLocationCoordinate2D] = [start]

        for i in 0..<waypointCount {
            let fraction = Double(i) / Double(waypointCount)
            let angle = biasAngle + (fraction * 2.0 * .pi)

            let jitter = Double.random(in: 0.8...1.2)
            let r = radiusDegrees * jitter

            let centerOffsetLat: Double
            let centerOffsetLon: Double
            if biasToward != nil {
                centerOffsetLat = radiusDegrees * 0.3 * cos(biasAngle)
                centerOffsetLon = radiusDegrees * 0.3 * sin(biasAngle) / cos(start.latitude * .pi / 180)
            } else {
                centerOffsetLat = 0
                centerOffsetLon = 0
            }

            let lat = start.latitude + centerOffsetLat + r * cos(angle)
            let lon = start.longitude + centerOffsetLon + r * sin(angle) / cos(start.latitude * .pi / 180)

            waypoints.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        waypoints.append(start)
        return waypoints
    }

    // MARK: - Out and Back Generation

    private func generateOutAndBackWaypoints(
        start: CLLocationCoordinate2D,
        targetDistanceMiles: Double,
        biasToward: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D] {
        let halfDistanceDegrees = (targetDistanceMiles / 2.0) * 0.0145

        let angle: Double
        if let bias = biasToward {
            angle = bearing(from: start, to: bias)
        } else {
            angle = Double.random(in: 0..<(2.0 * .pi))
        }

        let farLat = start.latitude + halfDistanceDegrees * cos(angle)
        let farLon = start.longitude + halfDistanceDegrees * sin(angle) / cos(start.latitude * .pi / 180)
        let farPoint = CLLocationCoordinate2D(latitude: farLat, longitude: farLon)

        return [start, farPoint, start]
    }

    // MARK: - Helpers

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x)
    }

    /// Adjust waypoints to bring total routed distance closer to target.
    func adjustWaypoints(
        _ waypoints: [CLLocationCoordinate2D],
        around start: CLLocationCoordinate2D,
        scaleFactor: Double
    ) -> [CLLocationCoordinate2D] {
        return waypoints.map { wp in
            if wp.latitude == start.latitude && wp.longitude == start.longitude {
                return wp
            }
            let dLat = (wp.latitude - start.latitude) * scaleFactor
            let dLon = (wp.longitude - start.longitude) * scaleFactor
            return CLLocationCoordinate2D(
                latitude: start.latitude + dLat,
                longitude: start.longitude + dLon
            )
        }
    }
}
