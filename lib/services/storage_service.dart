import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/picked_media.dart';
import 'supabase_service.dart';

class StorageService {

  /// Upload from a PickedMedia (preferred — works on web and mobile).
  static Future<String> uploadPickedMedia({
    required PickedMedia media,
    required String folder,
  }) async {
    final contentType = _getContentType(media.extension);
    return await _uploadViaProxy(
      folder: folder,
      extension: media.extension,
      contentType: contentType,
      bytes: media.bytes,
    );
  }

  /// Upload from raw bytes (web-compatible).
  static Future<String> uploadImageBytes({
    required Uint8List bytes,
    required String folder,
    required String extension,
  }) async {
    final contentType = _getContentType(extension);
    return await _uploadViaProxy(
      folder: folder,
      extension: extension,
      contentType: contentType,
      bytes: bytes,
    );
  }

  /// Upload an image from bytes (web-compatible convenience method).
  static Future<String> uploadImage({
    required dynamic file,
    required String folder,
  }) async {
    Uint8List bytes;
    String ext = 'jpg';
    if (file is PickedMedia) {
      bytes = file.bytes;
      ext = file.extension;
    } else if (!kIsWeb && file is File) {
      bytes = await file.readAsBytes();
    } else if (file is Uint8List) {
      bytes = file;
    } else if (file is List<int>) {
      bytes = Uint8List.fromList(file);
    } else {
      throw ArgumentError('Expected PickedMedia, File, Uint8List, or List<int>');
    }
    return await _uploadViaProxy(
      folder: folder,
      extension: ext,
      contentType: _getContentType(ext),
      bytes: bytes,
    );
  }

  /// Upload a file from bytes (web-compatible convenience method).
  static Future<String> uploadFile({
    required dynamic file,
    required String folder,
    required String contentType,
    required String extension,
  }) async {
    Uint8List bytes;
    if (file is PickedMedia) {
      bytes = file.bytes;
    } else if (!kIsWeb && file is File) {
      bytes = await file.readAsBytes();
    } else if (file is Uint8List) {
      bytes = file;
    } else if (file is List<int>) {
      bytes = Uint8List.fromList(file);
    } else {
      throw ArgumentError('Expected PickedMedia, File, Uint8List, or List<int>');
    }
    return await _uploadViaProxy(
      folder: folder,
      extension: extension,
      contentType: contentType,
      bytes: bytes,
    );
  }

  static Future<String> _uploadViaProxy({
    required String folder,
    required String extension,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final token = session?.accessToken ?? AppConfig.supabaseAnonKey;

    // Ensure extension is strictly valid and normalized
    String safeExt = extension.toLowerCase().replaceAll('.', '').trim();
    const allowed = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'webm', 'pdf', 'm4a'];
    if (!allowed.contains(safeExt)) {
      safeExt = PickedMedia.detectExtension(bytes) ?? 'jpg';
    }
    if (safeExt == 'jpeg') safeExt = 'jpg';
    final safeContentType = _getContentType(safeExt);

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/functions/v1/upload-to-r2');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': safeContentType,
        'Authorization': 'Bearer $token',
        'apikey': AppConfig.supabaseAnonKey,
        'X-R2-Folder': folder,
        'X-R2-Extension': safeExt,
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['publicUrl'] as String;
    } else {
      throw Exception('Failed to upload file: ${response.statusCode} ${response.body}');
    }
  }

  static Future<void> deleteImage(String imageUrl) async {
    final uri = Uri.parse(imageUrl);
    final key = uri.path.substring(1);

    final data = await SupabaseService.callFunction('delete-r2-object', body: {
      'key': key,
    });

    if (data['success'] != true) {
      throw Exception('Failed to delete image: ${data['error']}');
    }
  }

  static String getOptimizedUrl(String imageUrl, {int? width, int? height}) {
    return imageUrl;
  }

  static String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
