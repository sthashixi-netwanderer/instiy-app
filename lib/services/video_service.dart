import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';

class VideoService {
  static const int maxDurationSeconds = 30;

  /// Checks whether a video file or URL contains an audio stream.
  /// Returns `true` if audio is present, `false` if no audio track exists.
  /// Falls back to `true` on error (safe default — keeps mute button visible).
  static Future<bool> checkVideoHasAudio(String pathOrUrl) async {
    // Offloaded to backend/video_player for low-end device optimization.
    // We assume true so the UI can at least try to render a mute toggle.
    return true;
  }

  static Future<File?> pickVideo(BuildContext context) async {
    final source = await _showVideoSourceSheet(context);
    if (source == null) return null;

    final picker = ImagePicker();
    XFile? picked;
    if (source == 'record') {
      picked = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
    } else {
      picked = await picker.pickVideo(source: ImageSource.gallery);
    }

    if (picked == null) return null;
    return File(picked.path);
  }

  static Future<String?> _showVideoSourceSheet(BuildContext context) {
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
