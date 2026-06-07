import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';

class ImagePickerSheet {
  static Future<File?> pickSingle(BuildContext context) async {
    final source = await _showSourceSheet(context, multiSelect: false);
    if (source == null) return null;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    return picked != null ? File(picked.path) : null;
  }

  static Future<List<File>> pickMultiple(BuildContext context) async {
    final source = await _showSourceSheet(context, multiSelect: true);
    if (source == null) return [];

    final picker = ImagePicker();

    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      return picked != null ? [File(picked.path)] : [];
    } else {
      final images = await picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      return images.map((x) => File(x.path)).toList();
    }
  }

  static Future<ImageSource?> _showSourceSheet(
    BuildContext context, {
    required bool multiSelect,
  }) {
    return showShadSheet<ImageSource>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: Text(multiSelect ? 'Add Photos' : 'Choose Photo'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SourceOption(
              icon: LucideIcons.camera,
              iconColor: AppTheme.accent,
              iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
              title: 'Camera',
              subtitle: 'Take a photo right now',
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            const SizedBox(height: 4),
            _SourceOption(
              icon: LucideIcons.image,
              iconColor: AppTheme.successMoss,
              iconBgColor: AppTheme.successMoss.withValues(alpha: 0.1),
              title: multiSelect ? 'Gallery (choose multiple)' : 'Gallery',
              subtitle: multiSelect ? 'Select multiple photos' : 'Choose from your gallery',
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
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
