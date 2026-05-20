import Foundation

struct DeepSeekWorkoutClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makePlan(
        split: WorkoutSplit,
        current: BodyMetrics?,
        previous: BodyMetrics?,
        goal: BodyGoal?,
        dietEntries: [DietEntry]
    ) async throws -> GymPlan {
        let trimmedKey = DeepSeekConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekNutritionError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(WorkoutChatRequest(
            split: split,
            current: current,
            previous: previous,
            goal: goal,
            dietEntries: dietEntries
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekNutritionError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let apiError = try? JSONDecoder().decode(WorkoutAPIErrorResponse.self, from: data) {
                throw DeepSeekNutritionError.server(apiError.error.message)
            }
            throw DeepSeekNutritionError.server("DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let chatResponse = try JSONDecoder().decode(WorkoutChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw DeepSeekNutritionError.invalidResponse
        }

        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleaned.data(using: .utf8) else {
            throw DeepSeekNutritionError.invalidResponse
        }

        let result = try JSONDecoder().decode(AIWorkoutResult.self, from: contentData)
        return GymPlan(
            title: result.title.isEmpty ? "\(split.rawValue) AI 计划" : result.title,
            intent: result.intent,
            split: split,
            blocks: result.blocks.map { PlanBlock(name: $0.name, detail: $0.detail) },
            exercises: result.exercises.map {
                PlanExercise(
                    name: $0.name,
                    equipment: $0.equipment,
                    prescription: $0.prescription,
                    minutes: max(1, $0.minutes),
                    met: max(1, $0.met),
                    estimatedCalories: max(0, $0.estimatedCalories)
                )
            },
            notes: result.notes
        )
    }
}

private struct WorkoutChatRequest: Encodable {
    var model = "deepseek-v4-flash"
    var messages: [WorkoutChatMessage]
    var thinking = WorkoutThinking(type: "disabled")
    var responseFormat = WorkoutResponseFormat(type: "json_object")
    var stream = false
    var temperature = 0.25
    var maxTokens = 1300

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case responseFormat = "response_format"
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }

    init(split: WorkoutSplit, current: BodyMetrics?, previous: BodyMetrics?, goal: BodyGoal?, dietEntries: [DietEntry]) {
        let intake = dietEntries.reduce(0) { $0 + $1.calories }
        let foodText = dietEntries.map { "\($0.meal.rawValue)：\($0.food)，\(Int($0.calories)) kcal" }.joined(separator: "；")
        let weightDelta = WorkoutChatRequest.diff(current?.weightKg, previous?.weightKg)
        let fatDelta = WorkoutChatRequest.diff(current?.bodyFatPercent, previous?.bodyFatPercent)
        let goalText = goal.map {
            "目标日期：\($0.targetDate.formatted(date: .numeric, time: .omitted))，目标体重：\($0.targetWeightKg.map { String(format: "%.1f kg", $0) } ?? "未设")，目标体脂：\($0.targetBodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "未设")，剩余天数：\($0.daysRemaining)"
        } ?? "未设置目标"

        messages = [
            WorkoutChatMessage(role: "system", content: """
            你是健身教练。根据用户当天食谱、最新身体数据、上次变化、目标体重体脂和截止日期，生成今日健身房训练计划。
            必须保持用户选择的分化部位，不要换训练日。输出 JSON，不要 Markdown。
            JSON 格式：
            {
              "title": "标题",
              "intent": "一句话说明今天为什么这样练",
              "blocks": [{"name": "热身", "detail": "内容"}],
              "exercises": [
                {"name": "动作", "equipment": "器械", "prescription": "组次", "minutes": 10, "met": 4.5, "estimatedCalories": 60}
              ],
              "notes": ["注意事项"]
            }
            规则：
            - exercises 给 5 到 7 个动作。
            - estimatedCalories 按用户体重、动作强度和分钟数估算；如果没有体重按 75kg。
            - 不给医疗建议，不使用极端减脂方案。
            - 如果目标压力过大，说明应优先可持续，不要盲目提高训练量。
            """),
            WorkoutChatMessage(role: "user", content: """
            今日分化：\(split.rawValue)
            最新体重：\(current?.weightKg.map { String(format: "%.1f kg", $0) } ?? "未知")
            最新体脂：\(current?.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "未知")
            较上次体重变化：\(weightDelta)
            较上次体脂变化：\(fatDelta)
            \(goalText)
            今日已记录摄入：\(Int(intake.rounded())) kcal
            今日食谱：\(foodText.isEmpty ? "未填写" : foodText)
            """)
        ]
    }

    private static func diff(_ current: Double?, _ previous: Double?) -> String {
        guard let current, let previous else { return "暂无" }
        return String(format: "%+.1f", current - previous)
    }
}

private struct WorkoutChatMessage: Codable {
    var role: String
    var content: String
}

private struct WorkoutThinking: Encodable {
    var type: String
}

private struct WorkoutResponseFormat: Encodable {
    var type: String
}

private struct WorkoutChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String?
    }
}

private struct WorkoutAPIErrorResponse: Decodable {
    var error: APIError

    struct APIError: Decodable {
        var message: String
    }
}

private struct AIWorkoutResult: Decodable {
    var title: String
    var intent: String
    var blocks: [Block]
    var exercises: [Exercise]
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case intent
        case blocks
        case exercises
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        intent = try container.decodeIfPresent(String.self, forKey: .intent) ?? "AI 已根据今日数据生成计划。"
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        exercises = try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? ["晚间请以健康/Fitness 实际运动数据为准。"]
    }

    struct Block: Decodable {
        var name: String
        var detail: String
    }

    struct Exercise: Decodable {
        var name: String
        var equipment: String
        var prescription: String
        var minutes: Double
        var met: Double
        var estimatedCalories: Double
    }
}
