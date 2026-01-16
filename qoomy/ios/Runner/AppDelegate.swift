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
}
