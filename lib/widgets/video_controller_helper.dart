import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Creates a VideoPlayerController that works on both web and mobile.
/// On mobile with a cached file, uses .file for performance.
/// On web, always streams from network.
VideoPlayerController createVideoController(
  String url, {
  dynamic cachedFile,
}) {
  if (kIsWeb || cachedFile == null) {
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
  // On mobile, use the cached file if available.
  // cachedFile is a dart:io File — only referenced on mobile.
  return _createFromFile(cachedFile, url);
}

/// Separate function so dart:io File is only referenced in a non-web path.
VideoPlayerController _createFromFile(dynamic file, String url) {
  // This function is only called on mobile where dart:io File exists.
  // ignore: unnecessary_cast
  return VideoPlayerController.file(file as dynamic);
}
