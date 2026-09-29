/// Web stub: call-recording segments are not captured on web (the mobile
/// flutter_webrtc MediaRecorder / record-package paths don't apply there).
class CallMicRecorder {
  Future<bool> hasPermission() async => false;

  Future<bool> start(String path) async => false;

  Future<String?> stop() async => null;

  Future<void> dispose() async {}

  static Future<void> deleteFile(String path) async {}
}
