import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Native recording helper using dart:io and record package.
class RecordingHelper {
  static final _audioRecorder = AudioRecorder();

  static Future<bool> hasPermission() => _audioRecorder.hasPermission();

  static Future<String> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );
    return path;
  }

  static Future<String?> stopRecording() => _audioRecorder.stop();

  static void dispose() => _audioRecorder.dispose();

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
