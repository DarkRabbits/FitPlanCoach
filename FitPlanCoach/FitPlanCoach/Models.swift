import Foundation

struct MeasurementSample: Codable, Equatable {
    var value: Double
    var date: Date
}

struct BodyMetrics: Codable, Equatable {
    var weightKg: Double?
    var weightDate: Date?
    var bodyFatPercent: Double?
    var bodyFatDate: Date?
    var capturedAt: Date

    var latestSourceDate: Date {
        [weightDate, bodyFatDate].compactMap { $0 }.max() ?? capturedAt
    }

    var fingerprint: String {
        let weight = weightKg.map { String(format: "%.2f", $0) } ?? "nil"
        let fat = bodyFatPercent.map { String(format: "%.2f", $0) } ?? "nil"
        let weightTime = weightDate?.timeIntervalSince1970 ?? 0
        let fatTime = bodyFatDate?.timeIntervalSince1970 ?? 0
        return "\(weight)-\(weightTime)-\(fat)-\(fatTime)"
    }
}

struct DietEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var meal: Meal = .breakfast
    var food: String
    var calories: Double
    var proteinGrams: Double?
    var carbGrams: Double?
    var fatGrams: Double?
}

struct NutritionEstimate: Equatable {
    var calories: Double
    var proteinGrams: Double
    var carbGrams: Double
    var fatGrams: Double
    var matchedFoods: [String]
    var note: String

    var hasMatches: Bool {
        !matchedFoods.isEmpty
    }
}

struct BodyGoal: Codable, Equatable {
    var targetDate: Date
    var targetWeightKg: Double?
    var targetBodyFatPercent: Double?
    var updatedAt: Date = Date()

    func weightDelta(from metrics: BodyMetrics?) -> Double? {
        guard let current = metrics?.weightKg, let targetWeightKg else { return nil }
        return current - targetWeightKg
    }

    func bodyFatDelta(from metrics: BodyMetrics?) -> Double? {
        guard let current = metrics?.bodyFatPercent, let targetBodyFatPercent else { return nil }
        return current - targetBodyFatPercent
    }

    var daysRemaining: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: targetDate)
        return max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    func weeklyWeightPace(from metrics: BodyMetrics?) -> Double? {
        guard let weightDelta = weightDelta(from: metrics), daysRemaining > 0 else { return nil }
        return weightDelta / (Double(daysRemaining) / 7)
    }
}

enum WorkoutSplit: String, CaseIterable, Codable, Identifiable {
    case backShoulders = "背 + 肩"
    case chestArms = "胸 + 手臂"
    case glutesLegsAbs = "臀腿 + 腹部"
    case backShouldersVolume = "背 + 肩 强化"
    case glutesArmsAbs = "臀腿 + 手臂 + 腹部"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .backShoulders:
            return "背肩"
        case .chestArms:
            return "胸臂"
        case .glutesLegsAbs:
            return "臀腿腹"
        case .backShouldersVolume:
            return "背肩强化"
        case .glutesArmsAbs:
            return "臀腿臂腹"
        }
    }

    static func defaultForToday(date: Date = Date()) -> WorkoutSplit {
        let weekday = Calendar.current.component(.weekday, from: date)
        let index = max(0, min(4, weekday - 2))
        return WorkoutSplit.allCases[index]
    }
}

enum Meal: String, CaseIterable, Codable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"

    var id: String { rawValue }
}

struct WorkoutSummary: Codable, Equatable {
    var workoutCount: Int
    var workoutCalories: Double
    var durationMinutes: Double
}

struct DailyEnergySummary: Codable, Equatable {
    var date: Date
    var intakeCalories: Double
    var activeEnergyCalories: Double
    var basalEnergyCalories: Double
    var workoutSummary: WorkoutSummary

    var totalExpenditure: Double {
        activeEnergyCalories + basalEnergyCalories
    }

    var calorieDeficit: Double {
        totalExpenditure - intakeCalories
    }

    var hasReliableBasalEnergy: Bool {
        basalEnergyCalories >= 300
    }
}

struct SavedWorkoutPlan: Codable, Equatable {
    var date: Date
    var createdAt: Date
    var split: WorkoutSplit
    var plan: GymPlan
}

struct GymPlan: Codable, Equatable {
    var title: String
    var intent: String
    var split: WorkoutSplit?
    var blocks: [PlanBlock]
    var exercises: [PlanExercise]
    var notes: [String]

    var estimatedTotalCalories: Double {
        exercises.reduce(0) { $0 + $1.estimatedCalories }
    }
}

struct PlanBlock: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var detail: String
}

struct PlanExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var equipment: String
    var prescription: String
    var minutes: Double
    var met: Double
    var estimatedCalories: Double
}
