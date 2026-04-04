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

    // Route geometry for progress calculation
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeCumulativeDistances: [Double] = []
    private var routeTotalDistance: Double = 0

    private var currentRouteID: String?
    private var currentUID: String? { Auth.auth().currentUser?.uid }
    private var currentDisplayName: String? { Auth.auth().currentUser?.displayName }
    private var isSessionActive = false

    // Heartbeat & staleness
    private var heartbeatTimer: Timer?
    private var staleSweeTimer: Timer?
    /// Runners with timestamps older than this (in seconds) are considered stale and removed.
    private let staleThreshold: TimeInterval = 60

    init() {
        self.dbRef = Database.database().reference()
    }

    // MARK: - Cleanup Stale Entries (call on app launch)

    /// Remove any leftover Firebase entry for the current user across all routes.
    /// Call this on app launch to clean up ghost entries from prior crashes.
    func cleanupOwnStaleEntries() {
        guard let uid = currentUID else { return }

        let activeRunsRef = dbRef.child("activeRuns")
        activeRunsRef.observeSingleEvent(of: .value) { snapshot in
            for routeChild in snapshot.children {
                guard let routeSnapshot = routeChild as? DataSnapshot else { continue }
                if routeSnapshot.hasChild(uid) {
                    activeRunsRef.child(routeSnapshot.key).child(uid).removeValue()
                    AppLogger.network.info("Cleaned up stale entry for \(uid) in route \(routeSnapshot.key)")
                }
            }
        }
    }

    // MARK: - Start Live Session

    func startSession(routeID: Double, routeCoordinates: [CLLocationCoordinate2D]) {
        guard let uid = currentUID else { return }
        if isSessionActive { stopSession() }

        let routeKey = String(Int(routeID))
        self.currentRouteID = routeKey
        self.routeCoordinates = routeCoordinates
        precomputeRouteDistances()

        // Clear previous state
        runnersDict.removeAll()
        joinOrder.removeAll()
        liveRunners = []
        isSessionActive = true

        // Set up references
        userRef = dbRef.child("activeRuns").child(routeKey).child(uid)
        routeRef = dbRef.child("activeRuns").child(routeKey)

        // Auto-cleanup on disconnect
        userRef?.onDisconnectRemoveValue()

        // Write initial position
        var initialData: [String: Any] = [
            "la": 0.0,
            "lo": 0.0,
            "p": 0.0,
            "t": ServerValue.timestamp()
        ]
        if let name = currentDisplayName, !name.isEmpty {
            initialData["n"] = name
        }
        userRef?.setValue(initialData)

        // Subscribe to other runners via granular child events
        attachListeners()

        // Start heartbeat to keep our timestamp fresh (every 10s)
        startHeartbeat()

        // Start periodic sweep to remove stale runners (every 15s)
        startStaleSweep()
    }

    // MARK: - Publish Location

    func publishLocation(location: CLLocation, distanceMiles: Double, pace: String) {
        let progress = calculateRouteProgress(currentLocation: location.coordinate)

        var data: [String: Any] = [
            "la": location.coordinate.latitude,
            "lo": location.coordinate.longitude,
            "p": progress,
            "pa": pace,
            "t": ServerValue.timestamp()
        ]
        if let name = currentDisplayName, !name.isEmpty {
            data["n"] = name
        }
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
        // Deactivate session first to prevent callbacks from re-populating state
        isSessionActive = false

        // Stop timers
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        staleSweeTimer?.invalidate()
        staleSweeTimer = nil

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
            guard let self = self, self.isSessionActive else { return }
            let uid = snapshot.key
            self.runnersDict.removeValue(forKey: uid)
            self.joinOrder.removeAll { $0 == uid }
            self.publishRunners()
        }
    }

    private func handleRunnerUpdate(snapshot: DataSnapshot) {
        guard isSessionActive else { return }

        let uid = snapshot.key
        guard let data = snapshot.value as? [String: Any],
              let routeID = currentRouteID else { return }

        // Skip the current user — we manage their entry locally in publishLocation
        if uid == currentUID { return }

        // Check staleness — Firebase server timestamps are in milliseconds
        if let timestamp = data["t"] as? Double {
            let ageSeconds = (Date().timeIntervalSince1970 * 1000 - timestamp) / 1000
            if ageSeconds > staleThreshold {
                // Remove the stale entry from Firebase and local state
                routeRef?.child(uid).removeValue()
                runnersDict.removeValue(forKey: uid)
                joinOrder.removeAll { $0 == uid }
                publishRunners()
                AppLogger.network.debug("Removed stale runner \(uid) (age: \(Int(ageSeconds))s)")
                return
            }
        }

        // Track join order for anonymous labeling
        if !joinOrder.contains(uid) {
            joinOrder.append(uid)
        }
        let index = joinOrder.firstIndex(of: uid) ?? 0

        let currentProgress = data["p"] as? Double ?? 0
        let publishedPace = data["pa"] as? String ?? "--:--"
        let distanceMiles = currentProgress * routeTotalDistance * 0.000621371

        var runner = Runner(id: uid, data: data, routeID: routeID, runnerIndex: index)
        runner.pace = publishedPace
        runner.distanceMiles = distanceMiles

        runnersDict[uid] = runner
        publishRunners()
    }

    private func publishRunners() {
        guard isSessionActive else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.liveRunners = Array(self.runnersDict.values)
            }
        }
    }

    // MARK: - Heartbeat & Stale Sweep

    /// Periodically write a fresh server timestamp so other clients know we're alive.
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.userRef?.updateChildValues(["t": ServerValue.timestamp()])
        }
    }

    /// Periodically scan local runnersDict and query Firebase to remove stale entries.
    private func startStaleSweep() {
        staleSweeTimer?.invalidate()
        staleSweeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.sweepStaleRunners()
        }
    }

    private func sweepStaleRunners() {
        guard isSessionActive, let ref = routeRef, let myUID = currentUID else { return }

        ref.observeSingleEvent(of: .value) { [weak self] snapshot in
            guard let self = self, self.isSessionActive else { return }
            let now = Date().timeIntervalSince1970 * 1000 // ms

            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      childSnapshot.key != myUID,
                      let data = childSnapshot.value as? [String: Any],
                      let timestamp = data["t"] as? Double else { continue }

                let ageSeconds = (now - timestamp) / 1000
                if ageSeconds > self.staleThreshold {
                    ref.child(childSnapshot.key).removeValue()
                    self.runnersDict.removeValue(forKey: childSnapshot.key)
                    self.joinOrder.removeAll { $0 == childSnapshot.key }
                    AppLogger.network.debug("Sweep removed stale runner \(childSnapshot.key) (age: \(Int(ageSeconds))s)")
                }
            }
            self.publishRunners()
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
