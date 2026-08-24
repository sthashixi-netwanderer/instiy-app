import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/announcement_provider.dart';
import 'announcement_service.dart';
import 'navigation_service.dart';
import '../widgets/announcement_dialog.dart';

/// Watches named-route changes and pops up any admin announcement that
/// targets the entered screen (subject to the per-user view cap).
///
/// The announcement list comes from [announcementProvider] (Riverpod), which
/// stays fresh via realtime — a newly created admin announcement shows the
/// next time a targeted screen is visited, without an app restart.
///
/// Routes created via [AppTheme.fadeSlideRoute] carry their settings, so
/// `route.settings.name` is available for named pushes and replacements —
/// unnamed MaterialPageRoute pushes are simply ignored.
class AnnouncementObserver extends NavigatorObserver {
  final ProviderContainer container;

  AnnouncementObserver(this.container);

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
    final notifier = container.read(announcementProvider.notifier);
    await notifier.ensureLoaded();
    final announcement = await AnnouncementService.pendingFor(
      container.read(announcementProvider),
      routeName,
    );
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
