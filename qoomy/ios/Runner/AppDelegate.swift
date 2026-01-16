import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var badgeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Request notification permissions for badge
    UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { granted, error in
      if let error = error {
        print("Badge permission error: \(error)")
      }
      print("Badge permission granted: \(granted)")
    }

    // Register for remote notifications
    application.registerForRemoteNotifications()

    // Set minimum background fetch interval
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

    // Setup method channel for badge
    let controller = window?.rootViewController as! FlutterViewController
    badgeChannel = FlutterMethodChannel(name: "com.qoomy.qoomy/badge", binaryMessenger: controller.binaryMessenger)

    badgeChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setBadgeCount":
        if let args = call.arguments as? [String: Any],
           let count = args["count"] as? Int {
          DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
            print("Badge count set to: \(count)")
          }
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Count is required", details: nil))
        }
      case "resetBadge":
        DispatchQueue.main.async {
          UIApplication.shared.applicationIconBadgeNumber = 0
          print("Badge count reset to 0")
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle background fetch - iOS will periodically call this
  override func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("Background fetch triggered - requesting badge refresh from Flutter")
    // Notify Flutter to refresh badge count
    badgeChannel?.invokeMethod("refreshBadge", arguments: nil)
    // Give Flutter a moment to process, then complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
      completionHandler(.newData)
    }
  }

  // When app becomes active (returns from background), trigger badge refresh
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    print("App became active - requesting badge refresh from Flutter")
    badgeChannel?.invokeMethod("refreshBadge", arguments: nil)
  }
}
