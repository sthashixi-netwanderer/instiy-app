import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Native (mobile) media cache service using the local filesystem.
class MediaCacheService {
  MediaCacheService._();

  static const _mediaDirName = 'media_cache';
  static Directory? _cachedDir;

  static Future<Directory> get _cacheDir async {
    if (_cachedDir != null && await _cachedDir!.exists()) return _cachedDir!;

    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${appDir.path}/$_mediaDirName');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    _cachedDir = mediaDir;
    return mediaDir;
  }

  static String _fileName(String url) {
    final bytes = utf8.encode(url);
    int hash = 0;
    for (final b in bytes) {
      hash = ((hash << 5) + hash + b) & 0x7FFFFFFF;
    }
    final ext = url.split('.').last.split('?').first;
    final safeExt = ext.length <= 10 ? ext : ext.substring(0, 10);
    return '${hash.toRadixString(16)}.$safeExt';
  }

  static Future<File?> getCachedFile(String url) async {
    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/${_fileName(url)}');
      if (await file.exists()) return file;
    } catch (_) {}
    return null;
  }

  static Future<bool> isCached(String url) async {
    final file = await getCachedFile(url);
    return file != null;
  }

  static Future<File> downloadAndCache(String url) async {
    final existing = await getCachedFile(url);
    if (existing != null) return existing;

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Media download failed (${response.statusCode}): $url');
    }

    final dir = await _cacheDir;
    final file = File('${dir.path}/${_fileName(url)}');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  static Future<File> getFile(String url) async {
    final cached = await getCachedFile(url);
    if (cached != null) return cached;
    return downloadAndCache(url);
  }

  static Future<void> precache(String url) async {
    try {
      await downloadAndCache(url);
    } catch (e) {
      debugPrint('MediaCacheService.precache failed: $e');
    }
  }

  static Future<File> getFileBackground(String url) async {
    final cached = await getCachedFile(url);
    if (cached != null) return cached;
    return downloadAndCache(url);
  }

  static Future<void> removeFile(String url) async {
    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/${_fileName(url)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> clearCache() async {
    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _cachedDir = null;
      }
    } catch (_) {}
  }

  static Future<int> getCacheSize() async {
    int total = 0;
    try {
      final dir = await _cacheDir;
      await for (final entity in dir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }
}
