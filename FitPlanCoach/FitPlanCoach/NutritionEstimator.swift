import Foundation

enum NutritionEstimator {
    private struct FoodProfile {
        var name: String
        var aliases: [String]
        var defaultServingGrams: Double
        var caloriesPer100g: Double
        var proteinPer100g: Double
        var carbsPer100g: Double
        var fatPer100g: Double
    }

    static func estimate(description: String) -> NutritionEstimate {
        let text = normalized(description)
        guard !text.isEmpty else {
            return NutritionEstimate(calories: 0, proteinGrams: 0, carbGrams: 0, fatGrams: 0, matchedFoods: [], note: "输入食物后会自动估算")
        }

        let matches = matchedProfiles(in: text)

        guard !matches.isEmpty else {
            return fallbackEstimate(for: text)
        }

        let usedSingleGramValue = matches.count == 1 ? firstGramValue(in: text) : nil
        let totals = matches.reduce((calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0)) { total, match in
            let grams = gramsForFood(profile: match.0, alias: match.1, text: text, singleGramValue: usedSingleGramValue)
            let factor = grams / 100

            return (
                total.calories + match.0.caloriesPer100g * factor,
                total.protein + match.0.proteinPer100g * factor,
                total.carbs + match.0.carbsPer100g * factor,
                total.fat + match.0.fatPer100g * factor
            )
        }

        return NutritionEstimate(
            calories: rounded(totals.calories),
            proteinGrams: rounded(totals.protein),
            carbGrams: rounded(totals.carbs),
            fatGrams: rounded(totals.fat),
            matchedFoods: matches.map(\.0.name),
            note: matches.count == 1 ? "按常见份量估算，可在描述里写克数提高准确度" : "已按识别出的食物分别估算"
        )
    }

    private static func gramsForFood(profile: FoodProfile, alias: String, text: String, singleGramValue: Double?) -> Double {
        if let grams = gramsNear(alias: alias, in: text) {
            return grams
        }

        if let singleGramValue {
            return singleGramValue
        }

        let servings = servingCountNear(alias: alias, in: text) ?? globalServingCount(in: text) ?? 1
        let modifier = portionModifier(in: text)
        return profile.defaultServingGrams * servings * modifier
    }

    private static func matchedProfiles(in text: String) -> [(FoodProfile, String)] {
        let candidates = profiles.flatMap { profile in
            profile.aliases.compactMap { alias -> (FoodProfile, String, NSRange)? in
                guard let range = text.range(of: alias) else { return nil }
                return (profile, alias, NSRange(range, in: text))
            }
        }
        .sorted {
            if $0.2.length == $1.2.length {
                return $0.2.location < $1.2.location
            }
            return $0.2.length > $1.2.length
        }

        var usedRanges: [NSRange] = []
        var usedNames = Set<String>()
        var results: [(FoodProfile, String)] = []

        for candidate in candidates {
            guard !usedNames.contains(candidate.0.name) else { continue }
            guard !usedRanges.contains(where: { rangesOverlap($0, candidate.2) }) else { continue }
            usedNames.insert(candidate.0.name)
            usedRanges.append(candidate.2)
            results.append((candidate.0, candidate.1))
        }

        return results
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    private static func fallbackEstimate(for text: String) -> NutritionEstimate {
        let servings = globalServingCount(in: text) ?? 1
        let isMeal = ["饭", "面", "粉", "套餐", "便当", "沙拉", "汉堡", "披萨", "粥"].contains { text.contains($0) }
        let calories = (isMeal ? 550 : 300) * servings
        let protein = (isMeal ? 24 : 12) * servings
        let carbs = (isMeal ? 65 : 30) * servings
        let fat = (isMeal ? 18 : 10) * servings

        return NutritionEstimate(
            calories: calories,
            proteinGrams: protein,
            carbGrams: carbs,
            fatGrams: fat,
            matchedFoods: [],
            note: "未命中具体食物，按普通一餐粗估"
        )
    }

    private static func gramsNear(alias: String, in text: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
        let patterns = [
            "\(escaped)\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(克|g)",
            "([0-9]+(?:\\.[0-9]+)?)\\s*(克|g)\\s*\(escaped)"
        ]
        return patterns.compactMap { firstNumber(matching: $0, in: text) }.first
    }

    private static func firstGramValue(in text: String) -> Double? {
        firstNumber(matching: "([0-9]+(?:\\.[0-9]+)?)\\s*(克|g)", in: text)
    }

    private static func servingCountNear(alias: String, in text: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
        let patterns = [
            "\(escaped)\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(个|只|颗|根|片|碗|杯|份|勺|块)",
            "([0-9]+(?:\\.[0-9]+)?)\\s*(个|只|颗|根|片|碗|杯|份|勺|块)\\s*\(escaped)"
        ]
        return patterns.compactMap { firstNumber(matching: $0, in: text) }.first
    }

    private static func globalServingCount(in text: String) -> Double? {
        if text.contains("半") { return 0.5 }
        if text.contains("两") { return 2 }
        if text.contains("三") { return 3 }
        return firstNumber(matching: "([0-9]+(?:\\.[0-9]+)?)\\s*(个|只|颗|根|片|碗|杯|份|勺|块)", in: text)
    }

    private static func portionModifier(in text: String) -> Double {
        if text.contains("少量") || text.contains("小份") || text.contains("小碗") {
            return 0.7
        }
        if text.contains("大份") || text.contains("大碗") || text.contains("加量") {
            return 1.35
        }
        return 1
    }

    private static func firstNumber(matching pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "＋", with: "+")
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static let profiles: [FoodProfile] = [
        FoodProfile(name: "米饭", aliases: ["米饭", "白饭", "饭"], defaultServingGrams: 180, caloriesPer100g: 116, proteinPer100g: 2.6, carbsPer100g: 25.9, fatPer100g: 0.3),
        FoodProfile(name: "糙米饭", aliases: ["糙米饭", "糙米"], defaultServingGrams: 180, caloriesPer100g: 111, proteinPer100g: 2.6, carbsPer100g: 23, fatPer100g: 0.9),
        FoodProfile(name: "面条", aliases: ["面条", "拉面", "拌面", "面"], defaultServingGrams: 220, caloriesPer100g: 138, proteinPer100g: 4.5, carbsPer100g: 25, fatPer100g: 2.1),
        FoodProfile(name: "燕麦", aliases: ["燕麦", "麦片"], defaultServingGrams: 50, caloriesPer100g: 389, proteinPer100g: 16.9, carbsPer100g: 66.3, fatPer100g: 6.9),
        FoodProfile(name: "全麦面包", aliases: ["全麦面包", "吐司", "面包"], defaultServingGrams: 70, caloriesPer100g: 247, proteinPer100g: 13, carbsPer100g: 41, fatPer100g: 4.2),
        FoodProfile(name: "红薯", aliases: ["红薯", "地瓜", "番薯"], defaultServingGrams: 180, caloriesPer100g: 86, proteinPer100g: 1.6, carbsPer100g: 20, fatPer100g: 0.1),
        FoodProfile(name: "土豆", aliases: ["土豆", "马铃薯"], defaultServingGrams: 180, caloriesPer100g: 77, proteinPer100g: 2, carbsPer100g: 17, fatPer100g: 0.1),
        FoodProfile(name: "鸡胸肉", aliases: ["鸡胸肉", "鸡胸", "鸡肉"], defaultServingGrams: 150, caloriesPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6),
        FoodProfile(name: "牛肉", aliases: ["牛肉", "牛排"], defaultServingGrams: 150, caloriesPer100g: 217, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 12),
        FoodProfile(name: "猪肉", aliases: ["猪肉", "瘦肉"], defaultServingGrams: 120, caloriesPer100g: 242, proteinPer100g: 27, carbsPer100g: 0, fatPer100g: 14),
        FoodProfile(name: "三文鱼", aliases: ["三文鱼", "鲑鱼"], defaultServingGrams: 150, caloriesPer100g: 208, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 13),
        FoodProfile(name: "虾", aliases: ["虾仁", "虾"], defaultServingGrams: 120, caloriesPer100g: 99, proteinPer100g: 24, carbsPer100g: 0.2, fatPer100g: 0.3),
        FoodProfile(name: "鸡蛋", aliases: ["鸡蛋", "蛋"], defaultServingGrams: 55, caloriesPer100g: 143, proteinPer100g: 12.6, carbsPer100g: 0.7, fatPer100g: 9.5),
        FoodProfile(name: "豆腐", aliases: ["豆腐"], defaultServingGrams: 150, caloriesPer100g: 76, proteinPer100g: 8, carbsPer100g: 1.9, fatPer100g: 4.8),
        FoodProfile(name: "牛奶", aliases: ["牛奶"], defaultServingGrams: 250, caloriesPer100g: 61, proteinPer100g: 3.2, carbsPer100g: 4.8, fatPer100g: 3.3),
        FoodProfile(name: "无糖酸奶", aliases: ["无糖酸奶", "希腊酸奶", "酸奶"], defaultServingGrams: 180, caloriesPer100g: 73, proteinPer100g: 9, carbsPer100g: 3.6, fatPer100g: 2),
        FoodProfile(name: "蛋白粉", aliases: ["蛋白粉", "乳清"], defaultServingGrams: 30, caloriesPer100g: 400, proteinPer100g: 80, carbsPer100g: 8, fatPer100g: 6),
        FoodProfile(name: "西兰花", aliases: ["西兰花", "西蓝花"], defaultServingGrams: 150, caloriesPer100g: 34, proteinPer100g: 2.8, carbsPer100g: 6.6, fatPer100g: 0.4),
        FoodProfile(name: "生菜沙拉", aliases: ["沙拉", "生菜"], defaultServingGrams: 180, caloriesPer100g: 45, proteinPer100g: 2, carbsPer100g: 8, fatPer100g: 1),
        FoodProfile(name: "香蕉", aliases: ["香蕉"], defaultServingGrams: 120, caloriesPer100g: 89, proteinPer100g: 1.1, carbsPer100g: 22.8, fatPer100g: 0.3),
        FoodProfile(name: "苹果", aliases: ["苹果"], defaultServingGrams: 180, caloriesPer100g: 52, proteinPer100g: 0.3, carbsPer100g: 14, fatPer100g: 0.2),
        FoodProfile(name: "牛油果", aliases: ["牛油果", "鳄梨"], defaultServingGrams: 100, caloriesPer100g: 160, proteinPer100g: 2, carbsPer100g: 8.5, fatPer100g: 14.7),
        FoodProfile(name: "坚果", aliases: ["坚果", "杏仁", "核桃", "腰果"], defaultServingGrams: 25, caloriesPer100g: 590, proteinPer100g: 20, carbsPer100g: 20, fatPer100g: 50),
        FoodProfile(name: "汉堡", aliases: ["汉堡"], defaultServingGrams: 210, caloriesPer100g: 250, proteinPer100g: 12, carbsPer100g: 26, fatPer100g: 11),
        FoodProfile(name: "披萨", aliases: ["披萨", "pizza"], defaultServingGrams: 180, caloriesPer100g: 266, proteinPer100g: 11, carbsPer100g: 33, fatPer100g: 10),
        FoodProfile(name: "奶茶", aliases: ["奶茶"], defaultServingGrams: 500, caloriesPer100g: 65, proteinPer100g: 1, carbsPer100g: 12, fatPer100g: 1.8)
    ]
}
