import Flutter
import UIKit
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
