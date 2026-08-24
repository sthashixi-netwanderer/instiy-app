import 'dart:async';

import 'package:flutter/material.dart';

import 'announcement_service.dart';
import 'navigation_service.dart';
import '../widgets/announcement_dialog.dart';

/// Watches named-route changes and pops up any admin announcement that
/// targets the entered screen (subject to the per-user view cap).
///
/// Routes created via [AppTheme.fadeSlideRoute] carry their settings, so
/// `route.settings.name` is available for named pushes and replacements —
/// unnamed MaterialPageRoute pushes are simply ignored.
class AnnouncementObserver extends NavigatorObserver {
  /// Lets the entered screen settle (and the splash → home transition
  /// finish) before a dialog appears on top of it.
  static const _showDelay = Duration(milliseconds: 800);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _maybeShow(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _maybeShow(newRoute);
  }

  void _maybeShow(Route<dynamic> route) {
    final routeName = route.settings.name;
    if (routeName == null || routeName.isEmpty) return;

    // Post-frame so the route is fully mounted, then a short delay so the
    // dialog doesn't fight the page transition.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_showDelay);
      await _showIfPending(routeName);
    });
  }

  Future<void> _showIfPending(String routeName) async {
    if (AnnouncementService.dialogVisible) return;
    await AnnouncementService.ensureLoaded();
    final announcement = await AnnouncementService.pendingFor(routeName);
    if (announcement == null) return;

    AnnouncementService.dialogVisible = true;
    try {
      await AnnouncementService.markShown(announcement);
      final context = NavigationService.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showAnnouncementDialog(context, announcement);
    } finally {
      AnnouncementService.dialogVisible = false;
    }
  }
}
