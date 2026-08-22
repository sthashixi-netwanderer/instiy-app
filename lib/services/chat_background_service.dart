import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_background_model.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

/// Stores chat background preferences locally (SharedPreferences + a cached
/// image copy in the app documents directory) and mirrors them to the
/// `chat_backgrounds` table, with custom images uploaded to R2 storage.
///
/// The local copy keeps rendering instant and works offline; the cloud row is
/// what makes the setting survive reinstalls, app-data clears and new
/// devices. When no local entry exists (fresh install / cleared data),
/// [getBackground] falls back to the cloud row and re-caches it locally.
class ChatBackgroundService {
  /// SharedPreferences key prefix. Keyed per user + (optional) conversation so
  /// global and per-conversation backgrounds don't collide.
  static const _prefsPrefix = 'chat_bg_';

  /// Sub-directory (inside app documents) where background images are cached.
  static const _imageDirName = 'chat_backgrounds';

  /// R2 folder custom background images are uploaded to.
  static const _r2Folder = 'chat-backgrounds';

  static String _prefsKey(String userId, String? conversationId) {
    return '$_prefsPrefix${userId}_${conversationId ?? 'global'}';
  }

  /// Returns (and lazily creates) the directory used to cache background images.
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
  /// one exists, then to the cloud row when nothing is stored locally.
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

    // 2. Fall back to the locally stored global background.
    final globalBg = _readFromPrefs(prefs, userId, null);
    if (globalBg != null) return globalBg;

    // 3. Nothing on-device — restore from the cloud (e.g. after a reinstall).
    try {
      final remote = await _fetchRemote(userId, conversationId) ??
          await _fetchRemote(userId, null);
      if (remote != null) {
        // Write through so subsequent loads skip the network round-trip.
        await prefs.setString(
          _prefsKey(userId, remote.conversationId),
          jsonEncode(remote.toJson()),
        );
      }
      return remote;
    } catch (e) {
      debugPrint('ChatBackgroundService: failed to load cloud background: $e');
      return null;
    }
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

      // If the stored image file no longer exists but we still have the R2
      // URL, keep the entry — the UI can render the remote image instead.
      if (bg.backgroundType == 'image' && bg.imageUrl == null) {
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

  /// Fetch a single background row from Supabase for user/conversation.
  static Future<ChatBackground?> _fetchRemote(
    String userId,
    String? conversationId,
  ) async {
    var query = SupabaseService.client
        .from('chat_backgrounds')
        .select()
        .eq('user_id', userId);
    query = conversationId != null
        ? query.eq('conversation_id', conversationId)
        : query.isFilter('conversation_id', null);
    final row = await query.maybeSingle();
    if (row == null) return null;
    return ChatBackground.fromJson(row);
  }

  /// Persist a chat background.
  ///
  /// When [sourceImagePath] is provided and [backgroundType] is 'image', the
  /// image is uploaded to R2 (canonical copy) and copied into the app's
  /// documents directory (offline cache); both paths are stored. Any
  /// previously stored image for this key is removed from disk and R2.
  ///
  /// Local storage always succeeds; the cloud mirror is best-effort so the
  /// feature still works offline (it just won't roam until next save online).
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

    final existing = _readFromPrefs(prefs, userId, conversationId);

    String? newImageUrl = existing?.imageUrl;
    String? finalImagePath =
        (backgroundType == 'image') ? existing?.localImagePath : null;

    if (backgroundType == 'image' && sourceImagePath != null) {
      // Upload the canonical copy to R2 first; fall back to keeping the old
      // URL when offline so the local-only behaviour is preserved.
      try {
        newImageUrl = await StorageService.uploadImage(
          file: File(sourceImagePath),
          folder: _r2Folder,
        );
      } catch (e) {
        debugPrint('ChatBackgroundService: R2 upload failed: $e');
      }

      // Remove the replaced image (local cache + R2 object).
      if (existing?.localImagePath != null) {
        await _deleteFileQuietly(existing!.localImagePath!);
      }
      finalImagePath = await _copyImageToLocalStore(
        sourceImagePath,
        userId: userId,
        conversationId: conversationId,
      );

      final oldUrl = existing?.imageUrl;
      if (oldUrl != null && oldUrl != newImageUrl) {
        _deleteRemoteImage(oldUrl);
      }
    } else if (backgroundType != 'image') {
      // Switching away from an image background — clean up both copies.
      if (existing?.localImagePath != null) {
        await _deleteFileQuietly(existing!.localImagePath!);
      }
      if (existing?.imageUrl != null) {
        _deleteRemoteImage(existing!.imageUrl!);
      }
      newImageUrl = null;
      finalImagePath = null;
    }

    final bg = ChatBackground(
      id: key,
      userId: userId,
      conversationId: conversationId,
      backgroundType: backgroundType,
      gradientName: backgroundType == 'gradient' ? gradientName : null,
      localImagePath: backgroundType == 'image' ? finalImagePath : null,
      imageUrl: backgroundType == 'image' ? newImageUrl : null,
      blurIntensity: blurIntensity,
    );

    await prefs.setString(key, jsonEncode(bg.toJson()));

    try {
      await _upsertRemote(bg);
    } catch (e) {
      debugPrint('ChatBackgroundService: failed to sync background: $e');
    }
    return bg;
  }

  /// Insert or update the cloud row. Done as select-then-write because
  /// `conversation_id` is nullable and Postgres UNIQUE constraints treat NULLs
  /// as distinct, which breaks `.upsert(onConflict: ...)` for the global row.
  static Future<void> _upsertRemote(ChatBackground bg) async {
    final client = SupabaseService.client;
    var query = client
        .from('chat_backgrounds')
        .select('id')
        .eq('user_id', bg.userId);
    query = bg.conversationId != null
        ? query.eq('conversation_id', bg.conversationId!)
        : query.isFilter('conversation_id', null);
    final existing = await query.maybeSingle();

    final payload = {
      'user_id': bg.userId,
      'conversation_id': bg.conversationId,
      'background_type': bg.backgroundType,
      'gradient_name': bg.gradientName,
      'image_url': bg.imageUrl,
      'blur_intensity': bg.blurIntensity,
    };

    if (existing != null) {
      await client
          .from('chat_backgrounds')
          .update(payload)
          .eq('id', existing['id'] as String);
    } else {
      await client.from('chat_backgrounds').insert(payload);
    }
  }

  static void _deleteRemoteImage(String url) {
    // Fire-and-forget: a leaked object is preferable to blocking the save.
    StorageService.deleteImage(url).catchError((e) {
      debugPrint('ChatBackgroundService: failed to delete R2 image: $e');
      return {};
    });
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
