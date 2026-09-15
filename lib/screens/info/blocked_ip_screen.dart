import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/supabase_service.dart';

/// Lockout shown when the worker reports the current public IP is blocked.
/// Pushed with pushAndRemoveUntil — there is no route back into the app.
class BlockedIpScreen extends StatefulWidget {
  const BlockedIpScreen({super.key, this.reason});

  final String? reason;

  @override
  State<BlockedIpScreen> createState() => _BlockedIpScreenState();
}

class _BlockedIpScreenState extends State<BlockedIpScreen> {
  @override
  void initState() {
    super.initState();
    // Drop the session locally so a blocked user doesn't stay signed in.
    unawaited(SupabaseService.auth.signOut());
  }

  @override
  Widget build(BuildContext context) {
    final reason = widget.reason?.trim();
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gpp_bad_outlined,
                  size: 72,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Access restricted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  (reason == null || reason.isEmpty)
                      ? 'Your network has been restricted from accessing '
                          'Instiy. If you believe this is a mistake, please '
                          'contact support.'
                      : 'Your network has been restricted from accessing '
                          'Instiy.\n\nReason: $reason',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
