import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/account_status_provider.dart';
import '../../providers/providers.dart';
import '../../services/report_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_button.dart';

class SuspendedScreen extends ConsumerStatefulWidget {
  const SuspendedScreen({super.key});

  @override
  ConsumerState<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends ConsumerState<SuspendedScreen> {
  final _complaintController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _complaintController.addListener(() => setState(() {}));
  }

  /// When the suspended screen is open and the admin unsuspends the user, the
  /// account-status watcher fires a global navigation to /home, but the user
  /// would miss the feedback. Show a confirmation toast before the route swap
  /// lands.
  void _onAccountStatusChanged(bool? previous, bool next) {
    if (previous == true && next == false) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Account Reinstated'),
          description: Text(
            'Your account has been reviewed and reinstated. Welcome back!',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    final text = _complaintController.text.trim();
    if (text.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Required'),
          description: Text(
            'Please describe your complaint before submitting.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(authProvider).user;
      if (user == null) throw Exception('Not authenticated');

      await ReportService.submitComplaint(
        userId: user.id,
        complaintText: text,
        reportId: user.suspendedReportId,
      );

      if (mounted) {
        setState(() {
          _submitted = true;
          _isSubmitting = false;
        });
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Complaint submitted'),
            description: Text(
              'Your complaint has been sent to our team for review.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text('Failed to submit complaint: $e'),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await ref.read(authProvider).signOut();
    if (mounted) {
      unawaited(
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(accountStatusProvider, _onAccountStatusChanged);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: context.rAll(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: context.rh(60)),

              // Warning icon
              Container(
                padding: context.rAll(20),
                decoration: BoxDecoration(
                  color: AppTheme.destructive.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.shieldOff,
                  size: context.ri(48),
                  color: AppTheme.destructive,
                ),
              ),

              SizedBox(height: context.rh(24)),

              Text(
                'Account Suspended',
                style: TextStyle(
                  fontSize: context.rsp(24),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: context.rh(12)),

              Text(
                'Your account has been suspended by an administrator. You are unable to use the app until your suspension is lifted.',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: context.rh(32)),

              if (_submitted) ...[
                Container(
                  padding: context.rAll(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(context.rr(12)),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.checkCircle,
                        color: AppTheme.accent,
                        size: context.ri(24),
                      ),
                      SizedBox(width: context.rw(12)),
                      Expanded(
                        child: Text(
                          'Your complaint has been submitted. Our team will review it and get back to you.',
                          style: TextStyle(
                            fontSize: context.rsp(13),
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.rh(24)),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Submit a Complaint',
                    style: TextStyle(
                      fontSize: context.rsp(16),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Believe this is a mistake? Tell us why your account should be reinstated.',
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ),
                SizedBox(height: context.rh(12)),
                ShadInput(
                  controller: _complaintController,
                  placeholder: const Text(
                    'Describe why your account should be reinstated...',
                  ),
                  maxLines: 5,
                ),
                SizedBox(height: context.rh(16)),
                AppButton(
                  onPressed:
                      (_isSubmitting ||
                          _complaintController.text.trim().isEmpty)
                      ? null
                      : _submitComplaint,
                  enabled: _complaintController.text.trim().isNotEmpty,
                  loading: _isSubmitting,
                  child: const Text('Submit Complaint'),
                ),
                SizedBox(height: context.rh(24)),
              ],

              // Sign out button
              AppButton.outline(
                onPressed: _signOut,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.logOut, size: context.ri(18)),
                    SizedBox(width: context.rw(8)),
                    const Flexible(child: Text('Sign Out')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
