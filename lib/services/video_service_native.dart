import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/picked_media.dart';

/// Extracts a JPEG thumbnail from a random point in the video timeline —
/// between 20% and 80% of the duration, so black intro/outro frames are
/// skipped. Returns null when the video can't be read.
Future<Uint8List?> generateVideoThumbnailBytes(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    var positionMs = -1;
    try {
      final info = await VideoCompress.getMediaInfo(path);
      final durationMs = info.duration ?? 0;
      if (durationMs > 1000) {
        final lo = (durationMs * 0.2).round();
        final hi = (durationMs * 0.8).round();
        if (hi > lo) positionMs = lo + math.Random().nextInt(hi - lo);
      }
    } catch (_) {}
    return await VideoCompress.getByteThumbnail(
      path,
      quality: 70,
      position: positionMs,
    );
  } catch (_) {
    return null;
  }
}

/// Native (mobile) video services using dart:io and video_compress.

/// Listing videos are capped at 30 seconds; anything longer is trimmed to
/// its first 30 seconds during publish. Keep in sync with the caption on
/// the create/edit listing screen and the source-sheet subtitles.
const int kMaxListingVideoSeconds = 30;

Future<PickedMedia?> pickVideoOrRecord(BuildContext context) async {
  final source = await _showVideoSourceSheet(context);
  if (source == null) return null;

  final picker = ImagePicker();
  XFile? picked;
  if (source == 'record') {
    picked = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 30),
    );
  } else {
    picked = await picker.pickVideo(source: ImageSource.gallery);
  }

  if (picked == null) return null;
  final file = File(picked.path);
  final bytes = await file.readAsBytes();

  // Tell the seller up front when a gallery video will be trimmed.
  if (source == 'gallery') {
    try {
      final info = await VideoCompress.getMediaInfo(picked.path);
      if ((info.duration ?? 0) > kMaxListingVideoSeconds * 1000 && context.mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.warningAmber,
            title: const Text(
              'Video longer than 30 seconds — only the first 30 seconds will be used when you publish.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  return PickedMedia(
    bytes: bytes,
    name: picked.name.isNotEmpty ? picked.name : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
    path: picked.path,
  );
}

/// Compress video on mobile using video_compress.
Future<PickedMedia?> compressVideoOrPass(PickedMedia media, {Function(String)? onProgress}) async {
  if (media.path == null) return null;
  try {
    onProgress?.call('Analyzing video...');

    final file = File(media.path!);
    final sizeMB = file.lengthSync() / (1024 * 1024);

    // Videos over 30s are cut to their first 30s — cutting requires a
    // re-encode, so this runs even when the file is already small.
    double? durationMs;
    try {
      durationMs = (await VideoCompress.getMediaInfo(media.path!)).duration;
    } catch (_) {}
    if (durationMs != null && durationMs > kMaxListingVideoSeconds * 1000) {
      onProgress?.call('Trimming video to the first $kMaxListingVideoSeconds seconds...');
      // NOTE: video_compress takes startTime/duration in SECONDS (both
      // platform implementations), unlike getMediaInfo().duration (ms).
      final trimmed = await VideoCompress.compressVideo(
        media.path!,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
        startTime: 0,
        duration: kMaxListingVideoSeconds,
      );
      if (trimmed != null && trimmed.file != null) {
        final trimmedSize = trimmed.file!.lengthSync() / (1024 * 1024);
        onProgress?.call('Trimmed to 30s (${trimmedSize.round()}MB)');
        final trimmedBytes = await trimmed.file!.readAsBytes();
        return PickedMedia(
          bytes: trimmedBytes,
          name: media.name,
          path: trimmed.file!.path,
        );
      }
      // Trim failed — fall through to plain compression, which at least
      // shrinks the upload.
    }

    if (sizeMB < 5) {
      onProgress?.call('Video already optimized');
      return null; // signal: use original
    }

    final info = await VideoCompress.compressVideo(
      media.path!,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      includeAudio: true,
      frameRate: 30,
    );

    if (info != null && info.file != null) {
      final compressedSize = info.file!.lengthSync() / (1024 * 1024);
      final savings = ((1 - compressedSize / sizeMB) * 100).round();
      onProgress?.call('Compressed ${sizeMB.round()}MB → ${compressedSize.round()}MB ($savings% smaller)');
      final bytes = await info.file!.readAsBytes();
      return PickedMedia(
        bytes: bytes,
        name: media.name,
        path: info.file!.path,
      );
    }
  } catch (e) {
    debugPrint('Video compression failed: $e');
    onProgress?.call('Using original (compression unavailable)');
  }

  return null; // signal: use original
}

Future<String?> _showVideoSourceSheet(BuildContext context) {
  return showShadSheet<String>(
    context: context,
    builder: (ctx) => ShadSheet(
      title: const Text('Add Product Video'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          _SourceOption(
            icon: LucideIcons.video,
            iconColor: AppTheme.accent,
            iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
            title: 'Record Video',
            subtitle: 'Record a short product video (max 30s)',
            onTap: () => Navigator.of(ctx).pop('record'),
          ),
          const SizedBox(height: 4),
          _SourceOption(
            icon: LucideIcons.folderOpen,
            iconColor: AppTheme.successMoss,
            iconBgColor: AppTheme.successMoss.withValues(alpha: 0.1),
            title: 'Choose from Gallery',
            subtitle: 'First 30s is used if the video is longer',
            onTap: () => Navigator.of(ctx).pop('gallery'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
