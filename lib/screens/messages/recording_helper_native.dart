import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Native recording helper using dart:io and record package.
class RecordingHelper {
  static final _audioRecorder = AudioRecorder();

  /// True once a recording session has been started on the shared recorder.
  /// The record plugin throws when dispose() is called without a session,
  /// so teardown must skip dispose when nothing was ever recorded.
  static bool _sessionStarted = false;

  static Future<bool> hasPermission() => _audioRecorder.hasPermission();

  static Future<String> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );
    _sessionStarted = true;
    return path;
  }

  static Future<String?> stopRecording() => _audioRecorder.stop();

  /// Pauses the active recording session. Audio captured so far is kept and
  /// [resumeRecording] continues writing to the same file.
  static Future<void> pauseRecording() => _audioRecorder.pause();

  /// Resumes a session paused by [pauseRecording] — the same file keeps
  /// growing, nothing recorded before the pause is lost.
  static Future<void> resumeRecording() => _audioRecorder.resume();

  /// Whether the current session is paused (false when idle/recording).
  static Future<bool> isPaused() => _audioRecorder.isPaused();

  /// Releases the shared recorder. Safe to call when no recording ever
  /// started, and idempotent across chat screens sharing the instance —
  /// teardown must never throw (previously reported to Crashlytics).
  static Future<void> dispose() async {
    if (!_sessionStarted) return;
    _sessionStarted = false;
    try {
      await _audioRecorder.dispose();
    } catch (_) {}
  }

  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<void> copyFile(String source, String dest) async {
    await File(source).copy(dest);
  }

  static Future<bool> fileExists(String path) => File(path).exists();

  static Future<String> getTempDir() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  static Future<String> getDocsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<Uint8List?> readFileBytes(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    return null;
  }
}
