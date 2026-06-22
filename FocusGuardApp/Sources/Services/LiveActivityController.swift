import ActivityKit
import Foundation
import SharedCore

@MainActor
final class LiveActivityController {
    func start(session: FocusSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FocusActivityAttributes(
            sessionID: session.id,
            goal: session.goal,
            startedAt: session.plannedStart,
            endsAt: session.plannedEnd
        )
        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(statusText: String(localized: "守住这一段时间")),
            staleDate: session.plannedEnd
        )
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func end(sessionID: UUID) async {
        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(statusText: String(localized: "本次专注已结束")),
            staleDate: nil
        )
        for activity in Activity<FocusActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
