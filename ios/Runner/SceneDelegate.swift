import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func windowScene(
    _ windowScene: UIScene,
    continue userActivity: NSUserActivity
  ) {
    // Handle Universal Links (instiy.com)
    let deepLinksChannel = FlutterMethodChannel(
      name: "plugins.flutter.io/deep_links",
      binaryMessenger: FlutterEngine(name: "engine")?.binaryMessenger
    )
  }
}
