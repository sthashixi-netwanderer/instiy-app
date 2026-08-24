import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/announcement_service.dart';
import '../utils/responsive.dart';

/// Admin-authored popup rendered as a glass dialog. Content is markdown
/// composed in the admin panel — text with emojis, links and images.
Future<void> showAnnouncementDialog(
  BuildContext context,
  AppAnnouncement announcement,
) {
  return AppTheme.showGlassDialog(
    context: context,
    title: Text(
      announcement.title.isEmpty ? 'Announcement' : announcement.title,
      style: TextStyle(
        fontSize: context.rsp(16),
        fontWeight: FontWeight.w700,
        color: AppTheme.charcoalInk,
      ),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: context.screenHeight * 0.5),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Markdown(
          data: announcement.content,
          shrinkWrap: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(fontSize: context.rsp(13.5), color: AppTheme.charcoalInk, height: 1.6),
            h1: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
            h2: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
            h3: TextStyle(fontSize: context.rsp(14.5), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
            listBullet: TextStyle(fontSize: context.rsp(13.5), color: AppTheme.charcoalInk),
            em: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.mutedSteel),
            strong: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
            a: TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.accent, width: 3)),
              color: AppTheme.accent.withValues(alpha: 0.05),
            ),
          ),
          imageBuilder: (uri, title, alt) => ClipRRect(
            borderRadius: BorderRadius.circular(context.rr(12)),
            child: CachedNetworkImage(
              imageUrl: uri.toString(),
              memCacheWidth: 720,
              fit: BoxFit.contain,
              placeholder: (_, _) => Container(
                height: context.rh(120),
                color: AppTheme.warmMist,
              ),
              errorWidget: (_, _, _) => Container(
                height: context.rh(120),
                color: AppTheme.warmMist,
                alignment: Alignment.center,
                child: Icon(LucideIcons.imageOff, size: context.ri(20), color: AppTheme.mutedSteel),
              ),
            ),
          ),
          onTapLink: (text, href, title) {
            if (href == null) return;
            final uri = Uri.tryParse(href);
            if (uri == null || !uri.hasScheme) return;
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          },
        ),
      ),
    ),
    actions: [
      ShadButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Got it'),
      ),
    ],
  );
}
