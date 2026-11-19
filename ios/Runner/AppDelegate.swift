// import Flutter
// import UIKit
//
// @main
// @objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
//   override func application(
//     _ application: UIApplication,
//     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//   ) -> Bool {
//     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//   }
//
//   func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
//     GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
//   }
// }


// import UIKit
// import Flutter
// import Firebase
// import FirebaseMessaging
// import GoogleMaps
// import CoreLocation
//
// @main
// @objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
//
//   private var locationManager: CLLocationManager?
//
//   override func application(
//     _ application: UIApplication,
//     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//   ) -> Bool {
//
//     FirebaseApp.configure()
//
//     application.registerForRemoteNotifications()
//     GMSServices.provideAPIKey("AIzaSyBibYoBPWBMMJC3spKxuKr7FVYZ7fsJW-Q")
//
//     GeneratedPluginRegistrant.register(with: self)
//
//     let lm = CLLocationManager()
//     lm.delegate = self
//     lm.allowsBackgroundLocationUpdates = true
//     lm.pausesLocationUpdatesAutomatically = false
//     if lm.authorizationStatus == .authorizedAlways {
//       lm.startMonitoringSignificantLocationChanges()
//     }
//     locationManager = lm
//
//     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//   }
//
//   func locationManager(_ manager: CLLocationManager,
//                        didUpdateLocations locations: [CLLocation]) {}
//
//   func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//     if manager.authorizationStatus == .authorizedAlways {
//       manager.startMonitoringSignificantLocationChanges()
//     }
//   }
// }


import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import GoogleMaps
import CoreLocation
import UserNotifications
@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {

  private var locationManager: CLLocationManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()

    application.registerForRemoteNotifications()
    GMSServices.provideAPIKey("AIzaSyBibYoBPWBMMJC3spKxuKr7FVYZ7fsJW-Q")

    GeneratedPluginRegistrant.register(with: self)
UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

    let lm = CLLocationManager()
    lm.delegate = self
    lm.allowsBackgroundLocationUpdates = true
    lm.pausesLocationUpdatesAutomatically = false
    if lm.authorizationStatus == .authorizedAlways {
      lm.startMonitoringSignificantLocationChanges()
    }
    locationManager = lm
 if launchOptions?[.location] != nil {
      let c = UNMutableNotificationContent()
      c.title = "Well Check"
      c.body = "Relaunched by location event"
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {}

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways {
      manager.startMonitoringSignificantLocationChanges()
    }
  }
}
