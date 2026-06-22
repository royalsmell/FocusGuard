import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusText: String
    }

    var sessionID: UUID
    var goal: String
    var startedAt: Date
    var endsAt: Date
}

