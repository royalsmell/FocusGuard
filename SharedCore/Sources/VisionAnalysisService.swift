import Foundation

public struct FrameAnalysisInput: Sendable {
    public let goal: String
    public let jpegData: Data
    public let recentLevels: [FocusLevel]

    public init(goal: String, jpegData: Data, recentLevels: [FocusLevel] = []) {
        self.goal = goal
        self.jpegData = jpegData
        self.recentLevels = recentLevels
    }
}

public struct SessionSummaryInput: Sendable {
    public let session: FocusSession

    public init(session: FocusSession) {
        self.session = session
    }
}

public protocol VisionAnalysisService: Sendable {
    func validateGoal(_ goal: String) async throws -> GoalFeedback
    func rewriteGoal(_ goal: String) async throws -> GoalRewriteResult
    func classifyFrame(_ input: FrameAnalysisInput) async throws -> FocusJudgment
    func summarizeSession(_ input: SessionSummaryInput) async throws -> String
}

public enum VisionServiceError: LocalizedError, Equatable {
    case invalidResponse
    case server(status: Int, message: String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "AI 服务返回了无法识别的响应。")
        case .server(let status, let message): String(localized: "AI 服务错误（\(status)）：\(message)")
        case .invalidJSON(let text): String(localized: "AI 返回格式不正确：\(text.prefix(160))")
        }
    }
}

public actor OpenAICompatibleVisionService: VisionAnalysisService {
    private let provider: ProviderConfig
    private let apiKey: String
    private let session: URLSession

    public init(provider: ProviderConfig, apiKey: String, session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.session = session
    }

    public func validateGoal(_ goal: String) async throws -> GoalFeedback {
        let prompt = """
        判断这个专注目标是否清晰且可执行：\(goal)
        只返回 JSON：{"isClear":true,"suggestion":""}。
        如果不清晰，suggestion 用简体中文给出一句更具体的改写建议。
        """
        let text = try await request(messages: [.text(role: "user", content: prompt)], maxTokens: 180)
        return try decodeJSON(GoalFeedback.self, from: text)
    }

    public func rewriteGoal(_ goal: String) async throws -> GoalRewriteResult {
        let prompt = """
        把下面的专注任务改写为清晰、具体、在一次专注会话内可执行的简体中文目标：\(goal)
        保留用户原意，不虚构交付物、数量或截止时间。只返回严格 JSON，不要 Markdown：
        {"rewrittenGoal":"改写后的目标","reason":"一句话说明改写理由"}
        """
        let text = try await request(messages: [.text(role: "user", content: prompt)], maxTokens: 220)
        let result = try decodeJSON(GoalRewriteResult.self, from: text)
        guard !result.rewrittenGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionServiceError.invalidJSON(text)
        }
        return result
    }

    public func classifyFrame(_ input: FrameAnalysisInput) async throws -> FocusJudgment {
        let history = input.recentLevels.map(\.rawValue).joined(separator: ",")
        let prompt = """
        你是专注状态观察员。用户当前目标：\(input.goal)
        最近状态：\(history.isEmpty ? "无" : history)
        根据当前截图判断：focused=明显在推进目标；wandering=轻微偏离或边缘活动；distracted=明显从事无关娱乐或其他任务；unknown=无法可靠判断。
        不要根据静止画面推断用户离开。只返回严格 JSON，不要 Markdown：
        {"level":"focused|wandering|distracted|unknown","confidence":0.0,"reason":"简短理由","reminder":"温和且具体的一句提醒"}
        """
        let message = ChatMessage.image(
            role: "user",
            text: prompt,
            dataURL: "data:image/jpeg;base64,\(input.jpegData.base64EncodedString())"
        )
        let text = try await request(messages: [message], maxTokens: 260)
        return try decodeJSON(FocusJudgment.self, from: text)
    }

    public func summarizeSession(_ input: SessionSummaryInput) async throws -> String {
        let session = input.session
        let noteworthy = session.events
            .filter { $0.level == .wandering || $0.level == .distracted }
            .prefix(12)
            .map { "- \($0.level.displayName)：\($0.reason)" }
            .joined(separator: "\n")
        let prompt = """
        为这次专注会话写一段简体中文复盘，语气客观、友善，不夸大未观测时间。
        目标：\(session.goal)
        专注秒数：\(Int(session.breakdown.focusedSeconds))
        走神秒数：\(Int(session.breakdown.wanderingSeconds))
        分心秒数：\(Int(session.breakdown.distractedSeconds))
        未观测秒数：\(Int(session.breakdown.unknownSeconds))
        事件：\n\(noteworthy.isEmpty ? "无" : noteworthy)
        输出两段纯文本：第一段总结，第二段给下一次可执行建议。
        """
        return try await request(messages: [.text(role: "user", content: prompt)], maxTokens: 420)
    }

    private func request(messages: [ChatMessage], maxTokens: Int) async throws -> String {
        var request = URLRequest(url: provider.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: provider.model, messages: messages, maxTokens: maxTokens)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VisionServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw VisionServiceError.server(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = envelope.choices.first?.message.content, !content.isEmpty else {
            throw VisionServiceError.invalidResponse
        }
        return content
    }

    nonisolated func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let cleaned = Self.cleanJSON(text)
        guard let data = cleaned.data(using: .utf8) else { throw VisionServiceError.invalidJSON(text) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VisionServiceError.invalidJSON(cleaned)
        }
    }

    public static func cleanJSON(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.replacingOccurrences(of: "```json", with: "")
            result = result.replacingOccurrences(of: "```", with: "")
        }
        if let first = result.firstIndex(of: "{"), let last = result.lastIndex(of: "}") {
            result = String(result[first...last])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: ChatContent

    static func text(role: String, content: String) -> ChatMessage {
        ChatMessage(role: role, content: .text(content))
    }

    static func image(role: String, text: String, dataURL: String) -> ChatMessage {
        ChatMessage(role: role, content: .parts([
            .text(text),
            .imageURL(dataURL)
        ]))
    }
}

private enum ChatContent: Encodable {
    case text(String)
    case parts([ChatPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private enum ChatPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .init("type"))
            try container.encode(text, forKey: .init("text"))
        case .imageURL(let url):
            try container.encode("image_url", forKey: .init("type"))
            try container.encode(["url": url], forKey: .init("image_url"))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ value: String) { self.stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
