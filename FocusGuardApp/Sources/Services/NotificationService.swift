import Foundation
import SharedCore
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        let category = UNNotificationCategory(
            identifier: SharedConstants.notificationCategory,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        return granted
    }

    func scheduleSessionEnd(sessionID: UUID, goal: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "专注时间到了")
        content.body = String(localized: "“\(goal)”已结束。打开专注守望查看复盘；如开启了屏幕广播，请从系统录屏状态中停止。")
        content.sound = .default
        content.categoryIdentifier = SharedConstants.notificationCategory
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: endIdentifier(sessionID),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelSessionEnd(sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [endIdentifier(sessionID)])
    }

    private func endIdentifier(_ sessionID: UUID) -> String {
        "focusguard.session.end.\(sessionID.uuidString)"
    }
}
