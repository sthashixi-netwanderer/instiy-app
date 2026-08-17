import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_background_model.dart';

/// Stores chat background preferences entirely on-device.
///
/// - Settings (type, gradient, blur, local image path) live in SharedPreferences.
/// - Custom background images are copied into the app's documents directory.
///
/// Nothing is uploaded to the cloud. When the user clears the app data, both
/// the SharedPreferences entries and the copied image files are removed, so the
/// custom background is cleared automatically.
class ChatBackgroundService {
  /// SharedPreferences key prefix. Keyed per user + (optional) conversation so
  /// global and per-conversation backgrounds don't collide.
  static const _prefsPrefix = 'chat_bg_';

  /// Sub-directory (inside app documents) where background images are stored.
  static const _imageDirName = 'chat_backgrounds';

  static String _prefsKey(String userId, String? conversationId) {
    return '$_prefsPrefix${userId}_${conversationId ?? 'global'}';
  }

  /// Returns (and lazily creates) the directory used to store background images.
  static Future<Directory> _imageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _imageDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Load the saved background for a user/conversation.
  ///
  /// Falls back to the user's global background when no conversation-specific
  /// one exists, matching the previous remote behaviour.
  static Future<ChatBackground?> getBackground(
    String userId,
    String? conversationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try the conversation-specific background first.
    if (conversationId != null) {
      final convBg = _readFromPrefs(prefs, userId, conversationId);
      if (convBg != null) return convBg;
    }

    // 2. Fall back to the global background.
    return _readFromPrefs(prefs, userId, null);
  }

  static ChatBackground? _readFromPrefs(
    SharedPreferences prefs,
    String userId,
    String? conversationId,
  ) {
    final raw = prefs.getString(_prefsKey(userId, conversationId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final bg = ChatBackground.fromJson(json);

      // If the stored image file no longer exists (e.g. app data cleared),
      // treat the background as missing so we don't show a broken image.
      if (bg.backgroundType == 'image') {
        final path = bg.localImagePath;
        if (path == null || !File(path).existsSync()) {
          return null;
        }
      }
      return bg;
    } catch (e) {
      debugPrint('ChatBackgroundService: failed to parse saved background: $e');
      return null;
    }
  }

  /// Persist a chat background.
  ///
  /// When [sourceImagePath] is provided and [backgroundType] is 'image', the
  /// image file is copied into the app documents directory and its new path is
  /// stored. Any previously stored image for this key is deleted.
  static Future<ChatBackground> saveBackground({
    required String userId,
    String? conversationId,
    required String backgroundType,
    String? gradientName,
    String? sourceImagePath,
    required double blurIntensity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(userId, conversationId);

    // Clean up any previous image file for this key before saving a new state.
    final existing = _readFromPrefs(prefs, userId, conversationId);
    if (existing?.localImagePath != null) {
      final keepingSameImage = backgroundType == 'image' &&
          sourceImagePath == null;
      if (!keepingSameImage) {
        await _deleteFileQuietly(existing!.localImagePath!);
      }
    }

    String? finalImagePath =
        (backgroundType == 'image') ? existing?.localImagePath : null;

    if (backgroundType == 'image' && sourceImagePath != null) {
      finalImagePath = await _copyImageToLocalStore(
        sourceImagePath,
        userId: userId,
        conversationId: conversationId,
      );
    }

    final bg = ChatBackground(
      id: key,
      userId: userId,
      conversationId: conversationId,
      backgroundType: backgroundType,
      gradientName: backgroundType == 'gradient' ? gradientName : null,
      localImagePath: backgroundType == 'image' ? finalImagePath : null,
      blurIntensity: blurIntensity,
    );

    await prefs.setString(key, jsonEncode(bg.toJson()));
    return bg;
  }

  /// Copy the picked/cropped image into the app's documents directory and
  /// return the new absolute path.
  static Future<String> _copyImageToLocalStore(
    String sourcePath, {
    required String userId,
    String? conversationId,
  }) async {
    final dir = await _imageDir();
    final ext =
        p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final fileName =
        'bg_${userId}_${conversationId ?? 'global'}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = p.join(dir.path, fileName);
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> _deleteFileQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('ChatBackgroundService: failed to delete old image: $e');
    }
  }
}
