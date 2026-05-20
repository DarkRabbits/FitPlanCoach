import Foundation

enum PlanGenerator {
    static func makePlan(
        current: BodyMetrics?,
        previous: BodyMetrics?,
        split: WorkoutSplit,
        goal: BodyGoal?,
        intakeCalories: Double
    ) -> GymPlan {
        let bodyWeight = current?.weightKg ?? 75
        let weightDelta = delta(current?.weightKg, previous?.weightKg)
        let fatDelta = delta(current?.bodyFatPercent, previous?.bodyFatPercent)
        let intensity = intensityProfile(weightDelta: weightDelta, fatDelta: fatDelta, goal: goal, metrics: current, intakeCalories: intakeCalories)
        let exercises = exerciseTemplates(for: split).map { template in
            template.exercise(bodyWeightKg: bodyWeight, multiplier: intensity.multiplier)
        }

        return GymPlan(
            title: "\(split.rawValue) 日",
            intent: intensity.intent,
            split: split,
            blocks: [
                PlanBlock(name: "热身", detail: warmup(for: split)),
                PlanBlock(name: "训练节奏", detail: intensity.pace),
                PlanBlock(name: "收尾", detail: cooldown(for: split, intensity: intensity))
            ],
            exercises: exercises,
            notes: recommendationNotes(weightDelta: weightDelta, fatDelta: fatDelta, bodyWeight: current?.weightKg, goal: goal, metrics: current, intakeCalories: intakeCalories)
        )
    }

    static func deficitJudgement(for summary: DailyEnergySummary) -> String {
        guard summary.hasReliableBasalEnergy else {
            return "静息能量不足，缺口只能作趋势参考。Apple Watch/健康 App 产生静息能量后会更准。"
        }

        switch summary.calorieDeficit {
        case ..<0:
            return "今天是热量盈余。若目标是减脂，晚餐或加餐可以收一点。"
        case 0..<250:
            return "缺口偏小，适合维持或轻微减脂日。"
        case 250...700:
            return "缺口合理，减脂效率和恢复压力比较平衡。"
        case 700...950:
            return "缺口偏大，注意蛋白质、睡眠和明天训练表现。"
        default:
            return "缺口过大，不建议长期这样做；优先补足蛋白质和碳水。"
        }
    }

    static func comparisonText(current: BodyMetrics?, previous: BodyMetrics?) -> String {
        guard let current else { return "还没有读取到健康数据。" }
        guard let previous else { return "这是第一次记录，下一次会显示变化。" }

        var parts: [String] = []
        if let weightDelta = delta(current.weightKg, previous.weightKg) {
            parts.append("体重 \(signed(weightDelta, digits: 1)) kg")
        }
        if let fatDelta = delta(current.bodyFatPercent, previous.bodyFatPercent) {
            parts.append("体脂 \(signed(fatDelta, digits: 1))%")
        }

        return parts.isEmpty ? "本次没有可比较的体重或体脂变化。" : parts.joined(separator: "，")
    }

    private static func intensityProfile(
        weightDelta: Double?,
        fatDelta: Double?,
        goal: BodyGoal?,
        metrics: BodyMetrics?,
        intakeCalories: Double
    ) -> (intent: String, pace: String, multiplier: Double, cardioMinutes: Int) {
        let goalPressure = goalPressure(goal: goal, metrics: metrics)
        let intakePressure = intakeCalories >= 2400 ? 0.10 : intakeCalories >= 1900 ? 0.05 : 0

        if let weightDelta, weightDelta <= -0.8 {
            return (
                "体重下降较快，今天保留力量刺激但降低总量，优先恢复。",
                "每个动作保留 2-3 次余力，组间休息 90-120 秒。",
                max(0.78, 0.86 + intakePressure - goalPressure * 0.10),
                8
            )
        }

        if let fatDelta, fatDelta >= 0.3 {
            return (
                "体脂上行，今天在目标部位训练后提高一点总消耗。",
                "复合动作稳定发力，孤立动作缩短休息到 60-75 秒。",
                min(1.28, 1.12 + goalPressure * 0.10 + intakePressure),
                18 + Int(goalPressure * 8)
            )
        }

        if let weightDelta, weightDelta >= 0.6, (fatDelta ?? 0) >= 0 {
            return (
                "体重上行且体脂未下降，今天用容量训练拉高消耗。",
                "主项 90 秒休息，辅助动作 45-60 秒休息。",
                min(1.34, 1.18 + goalPressure * 0.08 + intakePressure),
                20 + Int(goalPressure * 8)
            )
        }

        return (
            goalPressure > 0.5 ? "目标压力偏高，今天在分化训练基础上略提高总消耗。" : "身体数据稳定，按分化计划推进训练质量。",
            "主项保留 1-2 次余力，辅助动作接近力竭但不牺牲动作。",
            min(1.22, 1 + goalPressure * 0.12 + intakePressure),
            12 + Int(goalPressure * 8)
        )
    }

    private static func warmup(for split: WorkoutSplit) -> String {
        switch split {
        case .backShoulders, .backShouldersVolume:
            return "划船机 6 分钟，加肩胛控制和弹力带外旋各 2 组。"
        case .chestArms:
            return "上斜走 6 分钟，加肩袖激活、俯卧撑各 2 组。"
        case .glutesLegsAbs, .glutesArmsAbs:
            return "坡度走 8 分钟，加髋屈伸、臀桥和徒手深蹲各 2 组。"
        }
    }

    private static func cooldown(for split: WorkoutSplit, intensity: (intent: String, pace: String, multiplier: Double, cardioMinutes: Int)) -> String {
        "Zone 2 有氧 \(intensity.cardioMinutes) 分钟，然后拉伸今天训练部位 5 分钟。"
    }

    private static func recommendationNotes(weightDelta: Double?, fatDelta: Double?, bodyWeight: Double?, goal: BodyGoal?, metrics: BodyMetrics?, intakeCalories: Double) -> [String] {
        var notes = ["器械热量为按体重和训练时长估算，晚间仍以健康/Fitness 实际数据为准。"]
        if let bodyWeight {
            notes.append("当前按 \(String(format: "%.1f", bodyWeight)) kg 估算训练消耗。")
        } else {
            notes.append("未读取到体重时按 75 kg 估算训练消耗。")
        }
        if let weightDelta {
            notes.append("上次到现在体重变化 \(signed(weightDelta, digits: 1)) kg。")
        }
        if let fatDelta {
            notes.append("体脂变化 \(signed(fatDelta, digits: 1))%。")
        }
        if let goal, let needLose = goal.weightDelta(from: metrics) {
            notes.append("距离目标体重还需减少 \(String(format: "%.1f", max(0, needLose))) kg，剩余 \(goal.daysRemaining) 天。")
        }
        if intakeCalories > 0 {
            notes.append("今日已记录摄入 \(Int(intakeCalories.rounded())) kcal，训练容量已参考这个数值。")
        }
        notes.append("今天食谱填写越完整，晚间热量缺口越可靠。")
        return notes
    }

    private static func goalPressure(goal: BodyGoal?, metrics: BodyMetrics?) -> Double {
        guard let goal, let weeklyPace = goal.weeklyWeightPace(from: metrics), weeklyPace > 0 else { return 0 }
        switch weeklyPace {
        case ..<0.35:
            return 0.15
        case 0.35..<0.65:
            return 0.45
        case 0.65..<0.95:
            return 0.75
        default:
            return 1.0
        }
    }

    private static func exerciseTemplates(for split: WorkoutSplit) -> [ExerciseTemplate] {
        switch split {
        case .backShoulders:
            return [
                ExerciseTemplate("高位下拉", "下拉器械", "4 组 x 8-12 次", 12, 4.8),
                ExerciseTemplate("坐姿划船", "划船器械", "4 组 x 8-12 次", 12, 5.0),
                ExerciseTemplate("单臂哑铃划船", "哑铃/训练凳", "3 组 x 10 次/侧", 10, 5.0),
                ExerciseTemplate("坐姿肩推", "肩推器械", "4 组 x 6-10 次", 11, 4.5),
                ExerciseTemplate("哑铃侧平举", "哑铃", "4 组 x 12-15 次", 9, 3.8),
                ExerciseTemplate("面拉", "绳索器械", "3 组 x 15 次", 8, 3.8)
            ]
        case .chestArms:
            return [
                ExerciseTemplate("杠铃卧推", "卧推架", "4 组 x 6-8 次", 13, 5.0),
                ExerciseTemplate("上斜哑铃推", "哑铃/上斜凳", "4 组 x 8-10 次", 12, 4.8),
                ExerciseTemplate("夹胸", "蝴蝶机/绳索", "3 组 x 12-15 次", 9, 3.8),
                ExerciseTemplate("绳索下压", "绳索器械", "4 组 x 10-12 次", 8, 3.5),
                ExerciseTemplate("哑铃弯举", "哑铃", "4 组 x 10-12 次", 8, 3.5),
                ExerciseTemplate("锤式弯举", "哑铃", "3 组 x 12 次", 7, 3.3)
            ]
        case .glutesLegsAbs:
            return [
                ExerciseTemplate("臀推", "臀推机/杠铃", "5 组 x 6-10 次", 14, 5.2),
                ExerciseTemplate("腿举", "腿举机", "4 组 x 10-12 次", 13, 5.0),
                ExerciseTemplate("罗马尼亚硬拉", "杠铃/哑铃", "4 组 x 8-10 次", 12, 5.5),
                ExerciseTemplate("腿弯举", "腿弯举机", "3 组 x 12 次", 8, 3.8),
                ExerciseTemplate("卷腹", "垫子/器械", "4 组 x 15 次", 8, 3.8),
                ExerciseTemplate("平板支撑", "垫子", "4 组 x 45 秒", 6, 3.2)
            ]
        case .backShouldersVolume:
            return [
                ExerciseTemplate("引体向上或辅助引体", "引体架/辅助器械", "4 组 x 6-10 次", 12, 5.5),
                ExerciseTemplate("胸托划船", "划船器械", "4 组 x 8-12 次", 12, 5.0),
                ExerciseTemplate("直臂下压", "绳索器械", "3 组 x 12-15 次", 8, 3.8),
                ExerciseTemplate("阿诺德推举", "哑铃", "4 组 x 8-10 次", 10, 4.5),
                ExerciseTemplate("反向飞鸟", "哑铃/反向飞鸟机", "4 组 x 12-15 次", 8, 3.6),
                ExerciseTemplate("耸肩", "哑铃/杠铃", "3 组 x 12 次", 7, 3.5)
            ]
        case .glutesArmsAbs:
            return [
                ExerciseTemplate("深蹲或哈克深蹲", "深蹲架/哈克机", "4 组 x 6-10 次", 13, 5.5),
                ExerciseTemplate("保加利亚分腿蹲", "哑铃/训练凳", "3 组 x 10 次/侧", 12, 5.3),
                ExerciseTemplate("臀外展", "臀外展机", "4 组 x 12-15 次", 8, 3.8),
                ExerciseTemplate("窄距卧推或臂屈伸", "卧推架/双杠", "3 组 x 8-10 次", 8, 4.2),
                ExerciseTemplate("EZ 杆弯举", "EZ 杆", "4 组 x 10-12 次", 8, 3.5),
                ExerciseTemplate("悬垂举腿", "单杠/罗马椅", "4 组 x 10-12 次", 8, 4.0)
            ]
        }
    }

    private static func calories(met: Double, bodyWeightKg: Double, minutes: Double) -> Double {
        ((met * 3.5 * bodyWeightKg) / 200) * minutes
    }

    private static func delta(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    private static func signed(_ value: Double, digits: Int) -> String {
        let format = "%+.\(digits)f"
        return String(format: format, value)
    }

    private struct ExerciseTemplate {
        var name: String
        var equipment: String
        var prescription: String
        var minutes: Double
        var met: Double

        init(_ name: String, _ equipment: String, _ prescription: String, _ minutes: Double, _ met: Double) {
            self.name = name
            self.equipment = equipment
            self.prescription = prescription
            self.minutes = minutes
            self.met = met
        }

        func exercise(bodyWeightKg: Double, multiplier: Double) -> PlanExercise {
            let adjustedMinutes = minutes * multiplier
            return PlanExercise(
                name: name,
                equipment: equipment,
                prescription: prescription,
                minutes: adjustedMinutes,
                met: met,
                estimatedCalories: PlanGenerator.calories(met: met, bodyWeightKg: bodyWeightKg, minutes: adjustedMinutes)
            )
        }
    }
}
