import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "tabekiri/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "initialize":
        result(true)
      case "requestPermission":
        ExpiryNotificationScheduler.requestPermission(result: result)
      case "syncReminders":
        guard let arguments = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "通知設定を読み取れませんでした。",
              details: nil
            )
          )
          return
        }
        let enabled = arguments["enabled"] as? Bool ?? false
        let reminders = arguments["reminders"] as? [[String: Any]] ?? []
        ExpiryNotificationScheduler.sync(
          enabled: enabled,
          reminders: reminders,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    notificationChannel = channel
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}

private enum ExpiryNotificationScheduler {
  private static let identifierPrefix = "tabekiri.expiry."
  private static let storedIdentifiersKey = "tabekiri_expiry_notification_ids"
  private static let maximumPendingReminders = 64

  static func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "permission_error",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(granted)
        }
      }
    }
  }

  static func sync(
    enabled: Bool,
    reminders: [[String: Any]],
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    let defaults = UserDefaults.standard
    let oldIdentifiers = defaults.stringArray(forKey: storedIdentifiersKey) ?? []
    center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

    guard enabled else {
      defaults.removeObject(forKey: storedIdentifiersKey)
      result(nil)
      return
    }

    let now = Date()
    let requests = reminders.prefix(maximumPendingReminders).compactMap { reminder in
      makeRequest(from: reminder, now: now)
    }
    let identifiers = requests.map(\.identifier)
    defaults.set(identifiers, forKey: storedIdentifiersKey)

    guard !requests.isEmpty else {
      result(nil)
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var firstError: Error?

    for request in requests {
      group.enter()
      center.add(request) { error in
        if let error {
          lock.lock()
          if firstError == nil {
            firstError = error
          }
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) {
      if let firstError {
        result(
          FlutterError(
            code: "schedule_error",
            message: firstError.localizedDescription,
            details: nil
          )
        )
      } else {
        result(nil)
      }
    }
  }

  private static func makeRequest(
    from reminder: [String: Any],
    now: Date
  ) -> UNNotificationRequest? {
    guard
      let id = reminder["id"] as? String,
      let title = reminder["title"] as? String,
      let body = reminder["body"] as? String,
      let scheduledAt = reminder["scheduledAt"] as? NSNumber
    else {
      return nil
    }

    let scheduledDate = Date(
      timeIntervalSince1970: scheduledAt.doubleValue / 1_000
    )
    guard scheduledDate > now else { return nil }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "EXPIRY_REMINDER"
    if let itemId = reminder["itemId"] as? String {
      content.userInfo = ["itemId": itemId]
    }

    let dateComponents = Calendar.autoupdatingCurrent.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: scheduledDate
    )
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: dateComponents,
      repeats: false
    )
    return UNNotificationRequest(
      identifier: identifierPrefix + id,
      content: content,
      trigger: trigger
    )
  }
}
