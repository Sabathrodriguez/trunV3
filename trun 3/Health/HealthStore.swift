//
//  HealthStore.swift
//  trun 3
//
//  Created by Sabath  Rodriguez on 1/21/26.
//

import HealthKit

class HealthStore: ObservableObject {
 
    let healthStore = HKHealthStore()
    
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
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
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
    
    func saveRun(startTime: Date, endTime: Date, distanceInMiles: Double, calories: Double, completion: @escaping (Bool, Error?) -> Void) {
        
        // 1. Create the workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
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
    
}
