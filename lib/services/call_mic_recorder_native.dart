import 'dart:io';

import 'package:record/record.dart';

/// Per-instance microphone recorder for call-recording segments. Deliberately
/// independent from the chat voice-note [RecordingHelper] (which shares one
/// static recorder) so a call can never collide with an in-chat voice note.
class CallMicRecorder {
  AudioRecorder? _recorder;
  bool _sessionStarted = false;

  Future<bool> hasPermission() async {
    try {
      return await (_recorder ??= AudioRecorder()).hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Starts writing an m4a segment at [path]. Returns false when the
  /// recorder could not start (permission revoked mid-call, plugin error).
  Future<bool> start(String path) async {
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (await recorder.isRecording()) return false;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _sessionStarted = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Finalizes the current segment and returns its file path (null when
  /// nothing was captured).
  Future<String?> stop() async {
    try {
      if (!_sessionStarted || _recorder == null) return null;
      if (!await _recorder!.isRecording()) return null;
      return await _recorder!.stop();
    } catch (_) {
      return null;
    }
  }

  /// Fully releases the recorder. A new instance starts on the next segment
  /// rotation, which sidesteps the plugin's stale-session quirks.
  Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    _sessionStarted = false;
    if (recorder == null) return;
    try {
      if (await recorder.isRecording()) await recorder.stop();
    } catch (_) {}
    try {
      await recorder.dispose();
    } catch (_) {}
  }

  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
