import Flutter
import UIKit
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Runs before scene connection and implicit engine creation, so
    // Crashlytics captures crashes during launch. GoogleService-Info.plist
    // is a Runner bundle resource; without the guard, a missing plist makes
    // FirebaseApp.configure() raise FIRAppException and crash at launch.
    // The Dart-side Firebase.initializeApp(options: DefaultFirebaseOptions…)
    // covers Firebase if the native configure is skipped here.
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
