//
//  HealthStore.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 1/21/26.
//

import HealthKit
import CoreLocation

class HealthStore: NSObject, ObservableObject, HKWorkoutSessionDelegate {

    let healthStore = HKHealthStore()
    @Published var weeklyDistances: [HKWorkoutActivityType: Double] = [.running: 0, .walking: 0, .cycling: 0]

    /// True when an Apple Watch recorded the same workout, so the phone should skip saving to avoid duplicates.
    @Published var watchRecordedWorkout = false

    // MARK: - Live Workout Session (background protection, iOS 26+)
    private var _workoutSession: Any?
    private var _liveBuilder: Any?

    /// Start an HKWorkoutSession so iOS keeps the app alive in the background.
    func startWorkoutSession(activityType: HKWorkoutActivityType) {
        guard #available(iOS 26.0, *) else { return }
        watchRecordedWorkout = false

        // If Watch starts a workout while ours is running, end ours to prevent conflict.
        // Background location (CLLocationManager) keeps the app alive regardless.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] _ in
            AppLogger.health.info("Apple Watch workout started mid-run — releasing phone session to avoid conflict")
            DispatchQueue.main.async {
                self?.watchRecordedWorkout = true
                self?.endWorkoutSession()
            }
        }

        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }

            self._workoutSession = session
            self._liveBuilder = builder
            AppLogger.health.info("Workout session started for background protection")
        } catch let hkError as HKError where hkError.code == .errorAnotherWorkoutSessionStarted {
            // Apple Watch already has an active workout — skip the phone-side session.
            // CLLocationManager background updates keep the app alive during the run.
            self.watchRecordedWorkout = true
            AppLogger.health.info("Apple Watch has an active workout — skipping phone-side session, relying on background location")
        } catch {
            AppLogger.health.error("Failed to start workout session: \(error)")
        }
    }

    /// End the live workout session. The workout is discarded because saveRun() handles persistence separately.
    func endWorkoutSession() {
        guard #available(iOS 26.0, *) else { return }
        guard let session = _workoutSession as? HKWorkoutSession else { return }
        let builder = _liveBuilder as? HKLiveWorkoutBuilder

        session.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder?.discardWorkout()
            self?._workoutSession = nil
            self?._liveBuilder = nil
            AppLogger.health.info("Workout session ended and discarded")
        }
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> ()) {
        // 1. Define the types you want to WRITE (Share)
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute()
        ]

        // 2. Define the types you want to READ (existing code)
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        // 3. Request authorization
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            completion(success, error)
        }
    }
    
    func fetchSteps(completion: @escaping (Double, Error?) -> ()) {
        let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepCountType, quantitySamplePredicate: predicate, completionHandler: {
            _, result, error in
            
            let stepCount = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            
            DispatchQueue.main.async {
                completion(stepCount, error)
            }
        })
        healthStore.execute(query)
    }
    
    func saveRun(startTime: Date, endTime: Date, distanceInMiles: Double, calories: Double, activityType: HKWorkoutActivityType, routeLocations: [CLLocation] = [], elevationGainMeters: Double = 0, completion: @escaping (Bool, Error?) -> Void) {

        // Skip saving if Apple Watch already recorded this workout to avoid duplicate data
        if watchRecordedWorkout {
            AppLogger.health.info("Apple Watch recorded this workout — skipping phone-side save to avoid duplicate")
            DispatchQueue.main.async { completion(true, nil) }
            return
        }

        // 1. Create the workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor

        // 2. Create the builder
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        // 3. Add elevation gain as workout metadata
        if elevationGainMeters > 0 {
            let elevationQuantity = HKQuantity(unit: .meter(), doubleValue: elevationGainMeters)
            builder.addMetadata([HKMetadataKeyElevationAscended: elevationQuantity]) { _, _ in }
        }

        // 4. Begin collection
        builder.beginCollection(withStart: startTime) { (success, error) in
            guard success else {
                completion(false, error)
                return
            }

            // 5. Create samples for the workout (Distance & Energy)
            let meters = distanceInMiles * 1609.34
            let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: meters)
            let distanceTypeIdentifier: HKQuantityTypeIdentifier = activityType == .cycling ? .distanceCycling : .distanceWalkingRunning
            let distanceSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: distanceTypeIdentifier)!, quantity: distanceQuantity, start: startTime, end: endTime)

            let caloriesQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
            let calorieSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!, quantity: caloriesQuantity, start: startTime, end: endTime)

            // 6. Add samples to the builder
            builder.add([distanceSample, calorieSample]) { (success, error) in
                guard success else {
                    completion(false, error)
                    return
                }

                // 7. End collection and Finish the workout
                builder.endCollection(withEnd: endTime) { (success, error) in
                    guard success else {
                        completion(false, error)
                        return
                    }

                    builder.finishWorkout { (workout, error) in
                        guard let workout = workout else {
                            DispatchQueue.main.async {
                                completion(false, error)
                            }
                            return
                        }

                        // 7. Attach route data if locations were captured
                        AppLogger.health.info("Workout saved. Route locations count: \(routeLocations.count)")
                        if !routeLocations.isEmpty {
                            self.addRouteToWorkout(workout: workout, locations: routeLocations) { routeSuccess, routeError in
                                if routeSuccess {
                                    AppLogger.health.info("Route saved successfully with \(routeLocations.count) points")
                                } else {
                                    AppLogger.health.error("Failed to save route: \(routeError?.localizedDescription ?? "unknown error")")
                                }
                                DispatchQueue.main.async {
                                    completion(true, nil)
                                }
                            }
                        } else {
                            AppLogger.health.debug("No route locations to save")
                            DispatchQueue.main.async {
                                completion(true, nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addRouteToWorkout(workout: HKWorkout, locations: [CLLocation], completion: @escaping (Bool, Error?) -> Void) {
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())

        routeBuilder.insertRouteData(locations) { success, error in
            guard success else {
                completion(false, error)
                return
            }

            routeBuilder.finishRoute(with: workout, metadata: nil) { route, error in
                completion(route != nil, error)
            }
        }
    }

    // MARK: - HKWorkoutSessionDelegate (observes watch-conflict session failures)

    @available(iOS 17.0, *)
    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        AppLogger.health.error("Workout session failed (Apple Watch conflict?): \(error)")
        _workoutSession = nil
        _liveBuilder = nil
    }

    @available(iOS 17.0, *)
    func workoutSession(
        _ session: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        AppLogger.health.debug("Workout session state: \(fromState.rawValue) → \(toState.rawValue)")
        if toState == .stopped || toState == .ended {
            _workoutSession = nil
            _liveBuilder = nil
        }
    }

    func fetchWeeklyDistances(completion: @escaping ([HKWorkoutActivityType: Double]) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startOfWeek, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
            var distances: [HKWorkoutActivityType: Double] = [
                .running: 0,
                .walking: 0,
                .cycling: 0
            ]

            if let error = error {
                AppLogger.health.error("Weekly distances query error: \(error.localizedDescription)")
            }

            guard let workouts = samples as? [HKWorkout] else {
                AppLogger.health.debug("No workout samples returned for weekly distances")
                DispatchQueue.main.async { completion(distances) }
                return
            }

            AppLogger.health.debug("Found \(workouts.count) workouts this week")

            for workout in workouts {
                let type = workout.workoutActivityType
                AppLogger.health.debug("Workout: type=\(type.rawValue), totalDistance=\(String(describing: workout.totalDistance))")
                if let totalDistance = workout.totalDistance {
                    let miles = totalDistance.doubleValue(for: .mile())
                    if distances.keys.contains(type) {
                        distances[type, default: 0] += miles
                    }
                }
            }

            DispatchQueue.main.async { completion(distances) }
        }

        healthStore.execute(query)
    }

}
