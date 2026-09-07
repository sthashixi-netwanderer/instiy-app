import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'navigation_service.dart';

/// Fire-and-forget submission runner for short flows (profile saves,
/// reports): the caller validates, shows its own "in progress" toast and
/// pops; [run] then executes the submission with no widget dependency and
/// reports the outcome as a toast over whatever screen the user is on.
class BackgroundSubmission {
  BackgroundSubmission._();

  static void run({
    required Future<void> Function() task,
    required String successTitle,
    String? successDescription,
    String failureTitle = 'Something went wrong',
  }) {
    unawaited(() async {
      try {
        await task();
        _showToast(
          ShadToast(
            title: Text(successTitle),
            description:
                successDescription == null ? null : Text(successDescription),
          ),
        );
      } catch (e) {
        debugPrint('Background submission failed: $e');
        _showToast(
          ShadToast.destructive(
            title: Text(failureTitle),
            description: Text('$e'),
          ),
        );
      }
    }());
  }

  /// ShadApp wraps the navigator with ShadToaster, so the root navigator's
  /// context resolves it — this works from anywhere after the submitting
  /// screen has popped.
  static void _showToast(ShadToast toast) {
    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) return;
    ShadToaster.of(context).show(toast);
  }
}
