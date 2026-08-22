import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Helper for sharing content through the native system share sheet.
///
/// Every share entry point in the app — product links, store links, video
/// links, generated files — should go through this helper so users always
/// get the OS share sheet (ACTION_SEND intent on Android,
/// UIActivityViewController on iOS, Web Share API on web) instead of an
/// in-app target picker.
class ShareHelper {
  ShareHelper._();

  /// Shares [text] (optionally containing URLs) via the system share sheet.
  ///
  /// [context] is optional and only used to derive the popover origin
  /// required on iPad, where the share sheet presents as an anchored popup.
  /// [subject] becomes the email subject when the user picks a mail app.
  ///
  /// Returns the [ShareResult] so callers can react to
  /// [ShareResultStatus.success] vs [ShareResultStatus.dismissed].
  static Future<ShareResult> shareText(
    String text, {
    BuildContext? context,
    String? subject,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: _originFrom(context),
      ),
    );
  }

  /// Shares local [files] (with optional accompanying [text]) via the
  /// system share sheet.
  ///
  /// Files must exist on disk — copy bytes to a temp file first (e.g. via
  /// `path_provider`) before calling. See also [shareText] for the meaning
  /// of [context] and [subject].
  static Future<ShareResult> shareFiles(
    List<XFile> files, {
    BuildContext? context,
    String? text,
    String? subject,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        files: files,
        text: text,
        subject: subject,
        sharePositionOrigin: _originFrom(context),
      ),
    );
  }

  /// Computes the iPad popover anchor rect from [context], or null when
  /// unavailable (Android/iOS phone/web don't need it).
  static Rect? _originFrom(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}