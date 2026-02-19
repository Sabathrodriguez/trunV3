//
//  LiveRunService.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import Foundation
import FirebaseAuth
import FirebaseDatabase
import CoreLocation
import SwiftUI

class LiveRunService: ObservableObject {
    @Published var liveRunners: [Runner] = []

    private var dbRef: DatabaseReference
    private var routeRef: DatabaseReference?
    private var userRef: DatabaseReference?

    private var addedHandle: DatabaseHandle?
    private var changedHandle: DatabaseHandle?
    private var removedHandle: DatabaseHandle?

    // Internal dictionary keyed by UID for efficient updates
    private var runnersDict: [String: Runner] = [:]
    // Track join order for anonymous labeling
    private var joinOrder: [String] = []
    // Track previous progress values for pace derivation
    private var previousProgress: [String: (progress: Double, time: Date)] = [:]

    // Route geometry for progress calculation
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeCumulativeDistances: [Double] = []
    private var routeTotalDistance: Double = 0

    private var currentRouteID: String?
    private var currentUID: String? { Auth.auth().currentUser?.uid }

    init() {
        self.dbRef = Database.database().reference()
    }

    // MARK: - Start Live Session

    func startSession(routeID: Double, routeCoordinates: [CLLocationCoordinate2D]) {
        guard let uid = currentUID else { return }

        let routeKey = String(Int(routeID))
        self.currentRouteID = routeKey
        self.routeCoordinates = routeCoordinates
        precomputeRouteDistances()

        // Clear previous state
        runnersDict.removeAll()
        joinOrder.removeAll()
        previousProgress.removeAll()
        liveRunners = []

        // Set up references
        userRef = dbRef.child("activeRuns").child(routeKey).child(uid)
        routeRef = dbRef.child("activeRuns").child(routeKey)

        // Auto-cleanup on disconnect
        userRef?.onDisconnectRemoveValue()

        // Write initial position
        let initialData: [String: Any] = [
            "la": 0.0,
            "lo": 0.0,
            "p": 0.0,
            "t": ServerValue.timestamp()
        ]
        userRef?.setValue(initialData)

        // Subscribe to other runners via granular child events
        attachListeners()
    }

    // MARK: - Publish Location

    func publishLocation(location: CLLocation, distanceMiles: Double, pace: String) {
        let progress = calculateRouteProgress(currentLocation: location.coordinate)

        let data: [String: Any] = [
            "la": location.coordinate.latitude,
            "lo": location.coordinate.longitude,
            "p": progress,
            "t": ServerValue.timestamp()
        ]
        userRef?.updateChildValues(data)

        // Update the local runner entry for the current user
        if let uid = currentUID, let routeID = currentRouteID {
            let runner = Runner(
                id: uid,
                name: "You",
                location: location.coordinate,
                color: Color.fromUID(uid),
                routeID: routeID,
                routeProgress: progress,
                pace: pace,
                distanceMiles: distanceMiles
            )
            runnersDict[uid] = runner
            publishRunners()
        }
    }

    // MARK: - Stop Session

    func stopSession() {
        // Remove listeners
        if let ref = routeRef {
            if let h = addedHandle { ref.removeObserver(withHandle: h) }
            if let h = changedHandle { ref.removeObserver(withHandle: h) }
            if let h = removedHandle { ref.removeObserver(withHandle: h) }
        }
        addedHandle = nil
        changedHandle = nil
        removedHandle = nil

        // Remove user's node
        userRef?.removeValue()
        userRef?.cancelDisconnectOperations()

        // Clear state
        runnersDict.removeAll()
        joinOrder.removeAll()
        previousProgress.removeAll()
        routeCoordinates.removeAll()
        routeCumulativeDistances.removeAll()
        routeTotalDistance = 0
        currentRouteID = nil
        routeRef = nil
        userRef = nil

        DispatchQueue.main.async {
            self.liveRunners = []
        }
    }

    // MARK: - Child Event Listeners

    private func attachListeners() {
        guard let ref = routeRef else { return }

        addedHandle = ref.observe(.childAdded) { [weak self] snapshot in
            self?.handleRunnerUpdate(snapshot: snapshot)
        }

        changedHandle = ref.observe(.childChanged) { [weak self] snapshot in
            self?.handleRunnerUpdate(snapshot: snapshot)
        }

        removedHandle = ref.observe(.childRemoved) { [weak self] snapshot in
            guard let self = self else { return }
            let uid = snapshot.key
            self.runnersDict.removeValue(forKey: uid)
            self.joinOrder.removeAll { $0 == uid }
            self.previousProgress.removeValue(forKey: uid)
            self.publishRunners()
        }
    }

    private func handleRunnerUpdate(snapshot: DataSnapshot) {
        let uid = snapshot.key
        guard let data = snapshot.value as? [String: Any],
              let routeID = currentRouteID else { return }

        // Filter stale entries (>30 seconds old)
        if let timestamp = data["t"] as? Double {
            let age = Date().timeIntervalSince1970 - (timestamp / 1000.0)
            if age > 30 { return }
        }

        // Track join order for anonymous labeling
        if !joinOrder.contains(uid) {
            joinOrder.append(uid)
        }
        let index = joinOrder.firstIndex(of: uid) ?? 0

        // Skip the current user — we manage their entry locally in publishLocation
        if uid == currentUID { return }

        // Derive pace from route progress delta
        let currentProgress = data["p"] as? Double ?? 0
        var derivedPace = "--:--"
        if let prev = previousProgress[uid], routeTotalDistance > 0 {
            let timeDelta = Date().timeIntervalSince(prev.time)
            let progressDelta = currentProgress - prev.progress
            if timeDelta > 0 && progressDelta > 0 {
                let distanceDeltaMiles = progressDelta * routeTotalDistance * 0.000621371
                let minutesDelta = timeDelta / 60.0
                let minutesPerMile = minutesDelta / distanceDeltaMiles
                let wholeMinutes = Int(minutesPerMile)
                let seconds = Int((minutesPerMile - Double(wholeMinutes)) * 60)
                if wholeMinutes < 60 {
                    derivedPace = String(format: "%d:%02d", wholeMinutes, seconds)
                }
            }
        }
        previousProgress[uid] = (progress: currentProgress, time: Date())

        let distanceMiles = currentProgress * routeTotalDistance * 0.000621371

        var runner = Runner(id: uid, data: data, routeID: routeID, runnerIndex: index)
        runner.pace = derivedPace
        runner.distanceMiles = distanceMiles

        runnersDict[uid] = runner
        publishRunners()
    }

    private func publishRunners() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.liveRunners = Array(self.runnersDict.values)
            }
        }
    }

    // MARK: - Route Progress Calculation

    private func precomputeRouteDistances() {
        routeCumulativeDistances = [0.0]
        var total: Double = 0

        for i in 1..<routeCoordinates.count {
            let prev = CLLocation(latitude: routeCoordinates[i-1].latitude,
                                  longitude: routeCoordinates[i-1].longitude)
            let curr = CLLocation(latitude: routeCoordinates[i].latitude,
                                  longitude: routeCoordinates[i].longitude)
            total += curr.distance(from: prev)
            routeCumulativeDistances.append(total)
        }
        routeTotalDistance = total
    }

    func calculateRouteProgress(currentLocation: CLLocationCoordinate2D) -> Double {
        guard routeCoordinates.count >= 2, routeTotalDistance > 0 else { return 0 }

        let loc = CLLocation(latitude: currentLocation.latitude,
                             longitude: currentLocation.longitude)

        var closestDistance = Double.greatestFiniteMagnitude
        var closestProgress: Double = 0

        for i in 0..<(routeCoordinates.count - 1) {
            let segStart = routeCoordinates[i]
            let segEnd = routeCoordinates[i + 1]

            let (projectedPoint, t) = projectPointOnSegment(
                point: currentLocation, segStart: segStart, segEnd: segEnd
            )

            let projected = CLLocation(latitude: projectedPoint.latitude,
                                       longitude: projectedPoint.longitude)
            let dist = loc.distance(from: projected)

            if dist < closestDistance {
                closestDistance = dist
                let segStartLoc = CLLocation(latitude: segStart.latitude,
                                             longitude: segStart.longitude)
                let segEndLoc = CLLocation(latitude: segEnd.latitude,
                                           longitude: segEnd.longitude)
                let segLength = segEndLoc.distance(from: segStartLoc)
                let distAlongSeg = t * segLength
                let totalDist = routeCumulativeDistances[i] + distAlongSeg
                closestProgress = totalDist / routeTotalDistance
            }
        }

        return min(max(closestProgress, 0), 1.0)
    }

    /// Projects a point onto a line segment, returns the projected coordinate and parameter t (0-1).
    private func projectPointOnSegment(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> (CLLocationCoordinate2D, Double) {
        let dx = segEnd.longitude - segStart.longitude
        let dy = segEnd.latitude - segStart.latitude
        let lenSq = dx * dx + dy * dy

        guard lenSq > 0 else {
            return (segStart, 0)
        }

        var t = ((point.longitude - segStart.longitude) * dx +
                 (point.latitude - segStart.latitude) * dy) / lenSq
        t = max(0, min(1, t))

        let projLat = segStart.latitude + t * dy
        let projLon = segStart.longitude + t * dx

        return (CLLocationCoordinate2D(latitude: projLat, longitude: projLon), t)
    }
}
