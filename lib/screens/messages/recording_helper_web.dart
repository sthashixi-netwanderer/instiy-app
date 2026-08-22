import 'dart:typed_data';

/// Web stub for recording — audio recording is not available on web.
class RecordingHelper {
  static Future<bool> hasPermission() async => false;
  static Future<String> startRecording() async => '';
  static Future<String?> stopRecording() async => null;

  // Pause/resume are no-ops on web — recording itself is unavailable.
  static Future<void> pauseRecording() async {}
  static Future<void> resumeRecording() async {}
  static Future<bool> isPaused() async => false;
  static void dispose() {}
  static Future<void> deleteFile(String path) async {}
  static Future<void> copyFile(String source, String dest) async {}
  static Future<bool> fileExists(String path) async => false;
  static Future<String> getTempDir() async => '/tmp';
  static Future<String> getDocsDir() async => '/tmp';
  static Future<Uint8List?> readFileBytes(String path) async => null;
}
