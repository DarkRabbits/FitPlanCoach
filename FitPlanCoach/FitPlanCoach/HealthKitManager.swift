import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case missingQuantityType(String)
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台设备不支持 HealthKit。请在 iPhone 真机上运行。"
        case .missingQuantityType(let name):
            return "系统不支持读取 \(name)。"
        case .authorizationDenied:
            return "未获得健康数据读取权限。请到系统设置或健康 App 中打开权限。"
        }
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }

        let readTypes: Set<HKObjectType> = Set([
            try quantityType(.bodyMass, name: "体重"),
            try quantityType(.bodyFatPercentage, name: "体脂率"),
            try quantityType(.activeEnergyBurned, name: "活动能量"),
            try quantityType(.basalEnergyBurned, name: "静息能量"),
            try quantityType(.dietaryEnergyConsumed, name: "膳食热量"),
            HKObjectType.workoutType()
        ])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
    }

    func fetchLatestBodyMetrics() async throws -> BodyMetrics {
        async let weight = latestQuantity(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            name: "体重",
            transform: { $0 }
        )

        async let bodyFat = latestQuantity(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            name: "体脂率",
            transform: { value in value * 100 }
        )

        let (weightSample, fatSample) = try await (weight, bodyFat)
        return BodyMetrics(
            weightKg: weightSample?.value,
            weightDate: weightSample?.date,
            bodyFatPercent: fatSample?.value,
            bodyFatDate: fatSample?.date,
            capturedAt: Date()
        )
    }

    func fetchTodayEnergySummary(intakeCalories: Double) async throws -> DailyEnergySummary {
        let day = Calendar.current.startOfDay(for: Date())
        let now = Date()

        async let active = cumulativeQuantity(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            name: "活动能量",
            start: day,
            end: now
        )
        async let basal = cumulativeQuantity(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            name: "静息能量",
            start: day,
            end: now
        )
        async let workouts = workoutSummary(start: day, end: now)

        let (activeCalories, basalCalories, workoutData) = try await (active, basal, workouts)
        return DailyEnergySummary(
            date: now,
            intakeCalories: intakeCalories,
            activeEnergyCalories: activeCalories,
            basalEnergyCalories: basalCalories,
            workoutSummary: workoutData
        )
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier, name: String) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.missingQuantityType(name)
        }
        return type
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        name: String,
        transform: @escaping (Double) -> Double
    ) async throws -> MeasurementSample? {
        let type = try quantityType(identifier, name: name)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: MeasurementSample(value: transform(value), date: sample.startDate))
            }
            healthStore.execute(query)
        }
    }

    private func cumulativeQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        name: String,
        start: Date,
        end: Date
    ) async throws -> Double {
        let type = try quantityType(identifier, name: name)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func workoutSummary(start: Date, end: Date) async throws -> WorkoutSummary {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let energyType = try quantityType(.activeEnergyBurned, name: "运动能量")

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                let calories = workouts.reduce(0) { total, workout in
                    let fromStatistics = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    let legacyTotal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    return total + (fromStatistics ?? legacyTotal ?? 0)
                }
                let durationMinutes = workouts.reduce(0) { $0 + ($1.duration / 60) }

                continuation.resume(returning: WorkoutSummary(
                    workoutCount: workouts.count,
                    workoutCalories: calories,
                    durationMinutes: durationMinutes
                ))
            }
            healthStore.execute(query)
        }
    }
}
