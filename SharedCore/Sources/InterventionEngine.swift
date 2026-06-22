import Foundation

public enum Intervention: Equatable, Sendable {
    case none
    case silent(message: String)
    case audible(message: String)
}

public struct InterventionEngine: Sendable {
    public var wanderingThreshold = 3
    public var distractedThreshold = 2
    public var wanderingCooldown: TimeInterval = 300
    public var distractedCooldown: TimeInterval = 60

    private var wanderingStreak = 0
    private var distractedStreak = 0
    private var lastWanderingAlert: Date?
    private var lastDistractedAlert: Date?

    public init() {}

    public mutating func register(_ judgment: FocusJudgment, at now: Date = .now) -> Intervention {
        guard judgment.confidence >= 0.65 else {
            resetStreaks()
            return .none
        }

        switch judgment.level {
        case .focused, .unknown:
            resetStreaks()
            return .none
        case .wandering:
            wanderingStreak += 1
            distractedStreak = 0
            guard wanderingStreak >= wanderingThreshold,
                  isReady(lastWanderingAlert, cooldown: wanderingCooldown, at: now) else {
                return .none
            }
            lastWanderingAlert = now
            wanderingStreak = 0
            return .silent(message: judgment.reminder)
        case .distracted:
            distractedStreak += 1
            wanderingStreak = 0
            guard distractedStreak >= distractedThreshold,
                  isReady(lastDistractedAlert, cooldown: distractedCooldown, at: now) else {
                return .none
            }
            lastDistractedAlert = now
            distractedStreak = 0
            return .audible(message: judgment.reminder)
        }
    }

    private mutating func resetStreaks() {
        wanderingStreak = 0
        distractedStreak = 0
    }

    private func isReady(_ last: Date?, cooldown: TimeInterval, at now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }
}

