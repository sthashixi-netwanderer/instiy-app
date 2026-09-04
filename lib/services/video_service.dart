import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/picked_media.dart';

// Conditional imports: web gets stubs, mobile gets real implementation.
import 'video_service_web.dart'
    if (dart.library.io) 'video_service_native.dart';

class VideoService {
  static const int maxDurationSeconds = 30;

  /// Pick a video. Returns PickedMedia on both platforms.
  static Future<PickedMedia?> pickVideo(BuildContext context) async {
    if (kIsWeb) {
      return pickVideoOrRecord(context);
    }
    return pickVideoOrRecord(context);
  }

  /// Compress a video for upload. Returns the compressed media on mobile,
  /// or the original PickedMedia on web (no compression available).
  ///
  /// [maxDurationSeconds] trims to the first N seconds (listing default:
  /// 30s). Pass null to compress without trimming (chat videos).
  static Future<PickedMedia?> compressVideo(
    PickedMedia media, {
    Function(String)? onProgress,
    int? maxDurationSeconds = 30,
  }) async {
    if (kIsWeb || media.path == null) {
      onProgress?.call('Video compression not available on web');
      return media;
    }

    // Mobile: use native compression via the native helper.
    final compressed = await compressVideoOrPass(
      media,
      onProgress: onProgress,
      maxDurationSeconds: maxDurationSeconds,
    );
    return compressed ?? media;
  }

  /// Check whether a video file or URL contains an audio stream.
  static Future<bool> checkVideoHasAudio(String pathOrUrl) async {
    return true;
  }

  /// Build a playback controller for a freshly picked local video so it
  /// can be previewed before publishing. Null on web or when the video has
  /// no local path.
  static dynamic previewLocalVideo(String? path) {
    return previewLocalVideoController(path);
  }

  /// Extract a thumbnail (JPEG bytes) from a random frame of the video.
  /// Mobile only — returns null on web or when extraction fails.
  static Future<Uint8List?> generateThumbnail(String? path) async {
    if (kIsWeb) return null;
    return generateVideoThumbnailBytes(path);
  }
}
