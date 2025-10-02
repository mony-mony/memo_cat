// import Flutter
// import UIKit
//
// @main
// @objc class AppDelegate: FlutterAppDelegate {
//   override func application(
//     _ application: UIApplication,
//     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//   ) -> Bool {
//     GeneratedPluginRegistrant.register(with: self)
//     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//   }
// }
import UIKit
import Flutter
import UserNotifications

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {

  let channelName = "memo.cat/wake"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

    // 알림 권한 요청
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      // granted 결과 필요시 처리
    }

    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "wakeNow" {
        let args = call.arguments as? [String: Any]
        let title = (args?["title"] as? String) ?? "메모냥이"
        let body  = (args?["body"]  as? String) ?? "탭하면 열려요"

        self.fireLocalNotification(title: title, body: body)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func fireLocalNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    // iOS 15+: timeSensitive (Capability 필요)
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
    let request = UNNotificationRequest(identifier: "memo_wake_\(UUID().uuidString)",
                                        content: content,
                                        trigger: trigger)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  // 포그라운드에서도 배너/사운드 표시
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    if #available(iOS 14.0, *) {
      return [.banner, .list, .sound]
    } else {
      return [.alert, .sound]
    }
  }
}
