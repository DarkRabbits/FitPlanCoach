import Foundation

enum DeepSeekNutritionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在 DeepSeekNutritionClient.swift 里填写 DeepSeek API Key。"
        case .invalidResponse:
            return "DeepSeek 返回内容无法解析，已可改用本地估算。"
        case .server(let message):
            return message
        }
    }
}

enum DeepSeekConfig {
    // Fill in your key here before running on device.
    // Example: static let apiKey = "sk-..."
    static let apiKey = ""

    static var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DeepSeekNutritionClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func estimate(description: String) async throws -> NutritionEstimate {
        let trimmedKey = DeepSeekConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekNutritionError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(foodDescription: description))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekNutritionError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw DeepSeekNutritionError.server(apiError.error.message)
            }
            throw DeepSeekNutritionError.server("DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
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

        let aiResult = try JSONDecoder().decode(AINutritionResult.self, from: contentData)
        return NutritionEstimate(
            calories: max(0, aiResult.calories),
            proteinGrams: max(0, aiResult.proteinGrams),
            carbGrams: max(0, aiResult.carbGrams),
            fatGrams: max(0, aiResult.fatGrams),
            matchedFoods: aiResult.items.map(\.name),
            note: aiResult.note.isEmpty ? "DeepSeek AI 拆解估算" : aiResult.note
        )
    }
}

private struct ChatRequest: Encodable {
    var model = "deepseek-v4-flash"
    var messages: [ChatMessage]
    var thinking = Thinking(type: "disabled")
    var responseFormat = ResponseFormat(type: "json_object")
    var stream = false
    var temperature = 0.1
    var maxTokens = 600

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case responseFormat = "response_format"
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }

    init(foodDescription: String) {
        messages = [
            ChatMessage(role: "system", content: """
            你是营养师。根据中文食物描述估算总热量和三大营养素。只输出 JSON，不要 Markdown。
            JSON 格式：
            {
              "calories": 0,
              "proteinGrams": 0,
              "carbGrams": 0,
              "fatGrams": 0,
              "items": [{"name": "食物", "calories": 0, "proteinGrams": 0, "carbGrams": 0, "fatGrams": 0}],
              "note": "简短说明"
            }
            数值用 kcal 和克。描述缺少份量时按常见一份估算。
            """),
            ChatMessage(role: "user", content: foodDescription)
        ]
    }
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct Thinking: Encodable {
    var type: String
}

private struct ResponseFormat: Encodable {
    var type: String
}

private struct ChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String?
    }
}

private struct APIErrorResponse: Decodable {
    var error: APIError

    struct APIError: Decodable {
        var message: String
    }
}

private struct AINutritionResult: Decodable {
    var calories: Double
    var proteinGrams: Double
    var carbGrams: Double
    var fatGrams: Double
    var items: [FoodItem]
    var note: String

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinGrams
        case carbGrams
        case fatGrams
        case items
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinGrams = try container.decodeIfPresent(Double.self, forKey: .proteinGrams) ?? 0
        carbGrams = try container.decodeIfPresent(Double.self, forKey: .carbGrams) ?? 0
        fatGrams = try container.decodeIfPresent(Double.self, forKey: .fatGrams) ?? 0
        items = try container.decodeIfPresent([FoodItem].self, forKey: .items) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? "DeepSeek AI 拆解估算"
    }

    struct FoodItem: Decodable {
        var name: String
        var calories: Double?
        var proteinGrams: Double?
        var carbGrams: Double?
        var fatGrams: Double?
    }
}
