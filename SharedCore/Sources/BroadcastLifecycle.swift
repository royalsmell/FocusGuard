import Foundation

public enum BroadcastLifecycle {
    public static func shouldFinish(
        active: ActiveSessionContext,
        authoritative: ActiveSessionContext?,
        now: Date
    ) -> Bool {
        guard now < active.endsAt,
              let authoritative,
              authoritative.sessionID == active.sessionID,
              now < authoritative.endsAt else {
            return true
        }
        return false
    }
}
