import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/picked_media.dart';

/// Native (mobile) video services using dart:io and video_compress.
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
            subtitle: 'Select an existing video',
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
