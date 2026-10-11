import Foundation
import HealthKit
import SwiftUI

@MainActor final class HealthBridge: ObservableObject {
    private let store = HKHealthStore()
    @Published var status = "Not connected"
    @Published var steps: Int?
    @Published var activeCalories: Int?
    @Published var bodyMass: Double?
    @Published var restingBPM: Int?
    @Published var sleepHours: Double?
    @Published var recentWorkouts: Int?
    @Published var busy = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
    }
    private var writeTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!
        ]
    }

    func connect() {
        guard isAvailable else { status = "Health data is unavailable on this device"; return }
        busy = true
        store.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                if let err { self.status = "Health access failed: \(err.localizedDescription)"; return }
                if ok {
                    UserDefaults.standard.set(true, forKey: "fit.healthRequested")
                    self.status = "Permission request completed"
                    self.refresh()
                } else {
                    self.status = "Health permissions were not granted"
                }
            }
        }
    }

    func refreshIfConnected() {
        if UserDefaults.standard.bool(forKey: "fit.healthRequested") { refresh() }
    }

    func refresh() {
        guard isAvailable else { status = "Health data unavailable"; return }
        readSum(.stepCount, unit: .count(), today: true) { self.steps = Int($0.rounded()) }
        readSum(.activeEnergyBurned, unit: .kilocalorie(), today: true) { self.activeCalories = Int($0.rounded()) }
        readLatest(.bodyMass, unit: .gramUnit(with: .kilo)) { self.bodyMass = $0 }
        readLatest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) { self.restingBPM = Int($0.rounded()) }
        readSleep()
        readWorkoutCount()
    }

    private func readSum(_ type: HKQuantityTypeIdentifier, unit: HKUnit, today: Bool, completion: @escaping @MainActor (Double) -> Void) {
        guard let quantity = HKObjectType.quantityType(forIdentifier: type) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = today ? HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate) : nil
        let query = HKStatisticsQuery(quantityType: quantity, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let value = result?.sumQuantity()?.doubleValue(for: unit) else { return }
            Task { @MainActor in completion(value) }
        }
        store.execute(query)
    }

    private func readLatest(_ type: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping @MainActor (Double) -> Void) {
        guard let quantity = HKObjectType.quantityType(forIdentifier: type) else { return }
        let query = HKSampleQuery(sampleType: quantity, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let value = sample.quantity.doubleValue(for: unit)
            Task { @MainActor in completion(value) }
        }
        store.execute(query)
    }

    private func readSleep() {
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let start = Date().addingTimeInterval(-36 * 3600)
        let query = HKSampleQuery(sampleType: sleep, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let seconds = (samples as? [HKCategorySample] ?? []).filter {
                let value = $0.value
                if #available(iOS 16.0, *) {
                    return value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                return value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if seconds > 0 { Task { @MainActor in self.sleepHours = seconds / 3600 } }
        }
        store.execute(query)
    }

    private func readWorkoutCount() {
        let from = Date().addingTimeInterval(-7 * 86400)
        let q = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForSamples(withStart: from, end: Date()), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let samples else { return }
            Task { @MainActor in self.recentWorkouts = samples.count }
        }
        store.execute(q)
    }

    func saveWorkout(_ workout: WorkoutRecord) {
        guard isAvailable, UserDefaults.standard.bool(forKey: "fit.healthRequested") else { return }
        let ended = workout.date
        let started = ended.addingTimeInterval(Double(-workout.minutes * 60))
        let activity: HKWorkoutActivityType = workout.name == "Cardio" ? .walking : .traditionalStrengthTraining
        let sample = HKWorkout(activityType: activity, start: started, end: ended)
        store.save(sample) { _, error in
            if let error { Task { @MainActor in self.status = "Workout Health sync failed: \(error.localizedDescription)" } }
        }
    }

    func saveFood(_ food: FoodRecord) {
        guard isAvailable, UserDefaults.standard.bool(forKey: "fit.healthRequested") else { return }
        let values: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, food.calories, .kilocalorie()),
            (.dietaryProtein, food.protein, .gram()),
            (.dietaryCarbohydrates, food.carbs, .gram()),
            (.dietaryFatTotal, food.fat, .gram())
        ]
        let samples: [HKQuantitySample] = values.compactMap { type, value, unit in
            guard value > 0, let kind = HKObjectType.quantityType(forIdentifier: type) else { return nil }
            return HKQuantitySample(type: kind, quantity: HKQuantity(unit: unit, doubleValue: value), start: food.date, end: food.date)
        }
        guard !samples.isEmpty else { return }
        store.save(samples) { _, error in
            if let error { Task { @MainActor in self.status = "Nutrition Health sync failed: \(error.localizedDescription)" } }
        }
    }
}
