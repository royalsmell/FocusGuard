import Foundation

public enum FocusLevel: String, Codable, CaseIterable, Sendable {
    case focused
    case wandering
    case distracted
    case unknown

    public var displayName: String {
        switch self {
        case .focused: String(localized: "专注")
        case .wandering: String(localized: "走神")
        case .distracted: String(localized: "分心")
        case .unknown: String(localized: "未观测")
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case active
    case completed
    case cancelled
}

public enum SessionMode: String, Codable, Sendable {
    case broadcastAI

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.broadcastAI.rawValue, "broadcastAIOnly", "hybridAI", "screenTimeOnly":
            self = .broadcastAI
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported session mode: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EventSource: String, Codable, Sendable {
    case visionAI
    case broadcast
    case system

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = rawValue == "screenTimeShield" ? .system : EventSource(rawValue: rawValue) ?? .system
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum BroadcastState: String, Codable, Sendable {
    case started
    case paused
    case resumed
    case stopped
}

public struct FocusJudgment: Codable, Equatable, Sendable {
    public let level: FocusLevel
    public let confidence: Double
    public let reason: String
    public let reminder: String

    public init(level: FocusLevel, confidence: Double, reason: String, reminder: String) {
        self.level = level
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
        self.reminder = reminder
    }
}

public struct GoalFeedback: Codable, Equatable, Sendable {
    public let isClear: Bool
    public let suggestion: String

    public init(isClear: Bool, suggestion: String) {
        self.isClear = isClear
        self.suggestion = suggestion
    }
}

public struct GoalRewriteResult: Codable, Equatable, Sendable {
    public let rewrittenGoal: String
    public let reason: String

    public init(rewrittenGoal: String, reason: String) {
        self.rewrittenGoal = rewrittenGoal
        self.reason = reason
    }
}

public struct FocusEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let source: EventSource
    public let level: FocusLevel
    public let confidence: Double
    public let reason: String
    public let reminder: String
    public let latencyMilliseconds: Int
    public let thumbnailRelativePath: String?
    public let broadcastState: BroadcastState?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date = .now,
        source: EventSource,
        level: FocusLevel,
        confidence: Double = 0,
        reason: String = "",
        reminder: String = "",
        latencyMilliseconds: Int = 0,
        thumbnailRelativePath: String? = nil,
        broadcastState: BroadcastState? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
        self.reminder = reminder
        self.latencyMilliseconds = latencyMilliseconds
        self.thumbnailRelativePath = thumbnailRelativePath
        self.broadcastState = broadcastState
    }
}

public struct FocusBreakdown: Codable, Equatable, Sendable {
    public var focusedSeconds: TimeInterval
    public var wanderingSeconds: TimeInterval
    public var distractedSeconds: TimeInterval
    public var unknownSeconds: TimeInterval

    public init(
        focusedSeconds: TimeInterval = 0,
        wanderingSeconds: TimeInterval = 0,
        distractedSeconds: TimeInterval = 0,
        unknownSeconds: TimeInterval = 0
    ) {
        self.focusedSeconds = focusedSeconds
        self.wanderingSeconds = wanderingSeconds
        self.distractedSeconds = distractedSeconds
        self.unknownSeconds = unknownSeconds
    }

    public var observedSeconds: TimeInterval {
        focusedSeconds + wanderingSeconds + distractedSeconds
    }

    public var totalSeconds: TimeInterval {
        observedSeconds + unknownSeconds
    }

    public var coverage: Double {
        guard totalSeconds > 0 else { return 0 }
        return observedSeconds / totalSeconds
    }
}

public struct FocusSession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var goal: String
    public var plannedStart: Date
    public var plannedEnd: Date
    public var actualEnd: Date?
    public var mode: SessionMode
    public var status: SessionStatus
    public var breakdown: FocusBreakdown
    public var summary: String?
    public var events: [FocusEvent]
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        goal: String,
        plannedStart: Date = .now,
        plannedEnd: Date,
        actualEnd: Date? = nil,
        mode: SessionMode,
        status: SessionStatus = .active,
        breakdown: FocusBreakdown = .init(),
        summary: String? = nil,
        events: [FocusEvent] = [],
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.goal = goal
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
        self.actualEnd = actualEnd
        self.mode = mode
        self.status = status
        self.breakdown = breakdown
        self.summary = summary
        self.events = events
        self.modifiedAt = modifiedAt
    }

    public var effectiveEnd: Date { actualEnd ?? plannedEnd }
    public var duration: TimeInterval { max(0, effectiveEnd.timeIntervalSince(plannedStart)) }

    private enum CodingKeys: String, CodingKey {
        case id, goal, plannedStart, plannedEnd, actualEnd, mode, status, breakdown, summary, events, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        goal = try container.decode(String.self, forKey: .goal)
        plannedStart = try container.decode(Date.self, forKey: .plannedStart)
        plannedEnd = try container.decode(Date.self, forKey: .plannedEnd)
        actualEnd = try container.decodeIfPresent(Date.self, forKey: .actualEnd)
        mode = try container.decode(SessionMode.self, forKey: .mode)
        status = try container.decode(SessionStatus.self, forKey: .status)
        breakdown = try container.decodeIfPresent(FocusBreakdown.self, forKey: .breakdown) ?? .init()
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        events = try container.decodeIfPresent([FocusEvent].self, forKey: .events) ?? []
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
            ?? actualEnd
            ?? plannedStart
    }
}

public struct ActiveSessionContext: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let goal: String
    public let startedAt: Date
    public let endsAt: Date
    public let mode: SessionMode
    public let provider: ProviderConfig?
    public let reminderPreferences: ReminderPreferences?
    public let analysisPreferences: AnalysisPreferences?

    public init(
        sessionID: UUID,
        goal: String,
        startedAt: Date,
        endsAt: Date,
        mode: SessionMode,
        provider: ProviderConfig?,
        reminderPreferences: ReminderPreferences? = nil,
        analysisPreferences: AnalysisPreferences? = nil
    ) {
        self.sessionID = sessionID
        self.goal = goal
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.mode = mode
        self.provider = provider
        self.reminderPreferences = reminderPreferences
        self.analysisPreferences = analysisPreferences
    }

    public var effectiveAnalysisPreferences: AnalysisPreferences {
        analysisPreferences ?? AnalysisPreferences()
    }
}
