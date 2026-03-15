//
//  HealthStore.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 1/21/26.
//

import HealthKit

class HealthStore: ObservableObject {

    let healthStore = HKHealthStore()
    @Published var weeklyDistances: [HKWorkoutActivityType: Double] = [.running: 0, .walking: 0, .cycling: 0]
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> ()) {
        // 1. Define the types you want to WRITE (Share)
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        // 2. Define the types you want to READ (existing code)
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.workoutType()
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
    
    func saveRun(startTime: Date, endTime: Date, distanceInMiles: Double, calories: Double, activityType: HKWorkoutActivityType, completion: @escaping (Bool, Error?) -> Void) {
        
        // 1. Create the workout configuration
        let configuration = HKWorkoutConfiguration()
//        configuration.activityType = .running
        configuration.activityType = activityType
        configuration.locationType = .outdoor
        
        // 2. Create the builder
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        // 3. Begin collection
        builder.beginCollection(withStart: startTime) { (success, error) in
            guard success else {
                completion(false, error)
                return
            }
            
            // 4. Create samples for the workout (Distance & Energy)
            // Note: HealthKit expects meters for distance
            let meters = distanceInMiles * 1609.34
            let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: meters)
            let distanceSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!, quantity: distanceQuantity, start: startTime, end: endTime)
            
            let caloriesQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
            let calorieSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!, quantity: caloriesQuantity, start: startTime, end: endTime)
            
            // 5. Add samples to the builder
            builder.add([distanceSample, calorieSample]) { (success, error) in
                guard success else {
                    completion(false, error)
                    return
                }
                
                // 6. End collection and Finish the workout
                builder.endCollection(withEnd: endTime) { (success, error) in
                    guard success else {
                        completion(false, error)
                        return
                    }
                    
                    builder.finishWorkout { (workout, error) in
                        DispatchQueue.main.async {
                            completion(workout != nil, error)
                        }
                    }
                }
            }
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
                print("[WeeklyDistances] Query error: \(error.localizedDescription)")
            }

            guard let workouts = samples as? [HKWorkout] else {
                print("[WeeklyDistances] No workout samples returned")
                DispatchQueue.main.async { completion(distances) }
                return
            }

            print("[WeeklyDistances] Found \(workouts.count) workouts this week")

            for workout in workouts {
                let type = workout.workoutActivityType
                print("[WeeklyDistances] Workout: type=\(type.rawValue), totalDistance=\(String(describing: workout.totalDistance))")
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
