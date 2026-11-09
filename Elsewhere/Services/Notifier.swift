import Foundation
import UserNotifications

/// 系统通知：后台操作（快捷键、自动跟随）的结果，以及「出口变了」的提醒。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static let exitChangedCategory = "EXIT_CHANGED"
    static let followAction = "FOLLOW"

    /// 用户点了「改过去」。
    var onFollow: (() -> Void)?

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let follow = UNNotificationAction(identifier: Self.followAction, title: "改过去", options: [])
        let category = UNNotificationCategory(identifier: Self.exitChangedCategory, actions: [follow],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: category ?? UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let isExitChange = response.notification.request.content.categoryIdentifier == Self.exitChangedCategory
        let tapped = response.actionIdentifier == Self.followAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if isExitChange && tapped {
            DispatchQueue.main.async { self.onFollow?() }
        }
        completionHandler()
    }
}
