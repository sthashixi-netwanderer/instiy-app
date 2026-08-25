import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/picked_media.dart';

/// Web stub for video services — video_compress and File are not available on web.
Future<PickedMedia?> pickVideoOrRecord(BuildContext context) async {
  final picker = ImagePicker();
  final xFile = await picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(seconds: 30),
  );

  if (xFile == null) return null;
  final bytes = await xFile.readAsBytes();
  return PickedMedia(
    bytes: bytes,
    name: xFile.name.isNotEmpty ? xFile.name : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
    path: null, // no filesystem on web
  );
}

/// On web, compression is not available — return null to signal "use original".
Future<PickedMedia?> compressVideoOrPass(
  PickedMedia media, {
  Function(String)? onProgress,
  int? maxDurationSeconds,
}) async {
  onProgress?.call('Video compression not available on web');
  return null;
}

/// On web, frame extraction is not available — chat video thumbnails are skipped.
Future<Uint8List?> generateVideoThumbnailBytes(String? path) async => null;
