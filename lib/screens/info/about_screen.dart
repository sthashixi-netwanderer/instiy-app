import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../utils/responsive.dart';
import '../../config/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, 
        title: const Text('About Instiy'),
        leading: ShadIconButton.ghost(
          icon: Icon(LucideIcons.arrowLeft, size: context.ri(24)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(20), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(20), context.rw(20), context.rh(20)),
        children: [
          // App info
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: context.rh(12)),
                Text(
                  'Instiy',
                  style: TextStyle(
                    fontSize: context.rsp(24),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                    fontFamily: 'Space Grotesk',
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  'Campus Marketplace',
                  style: TextStyle(fontSize: context.rsp(14), color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(24)),

          // Mission
          Container(
            padding: context.rAll(20),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(16)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Our Mission', style: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                SizedBox(height: context.rh(8)),
                Text(
                  'Instiy connects buyers and sellers across Ghanaian university campuses. Buy and sell textbooks, electronics, furniture, and more within your campus community.',
                  style: TextStyle(color: AppTheme.mutedSteel, height: 1.5, fontSize: context.rsp(13)),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(16)),

          // Legal links
          _AboutLinkRow(
            icon: LucideIcons.shield,
            iconColor: AppTheme.accent,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
          ),
          SizedBox(height: context.rh(8)),
          _AboutLinkRow(
            icon: LucideIcons.fileText,
            iconColor: AppTheme.accent,
            title: 'Terms & Conditions',
            subtitle: 'Rules for using Instiy',
            onTap: () => Navigator.of(context).pushNamed('/terms-conditions'),
          ),
          SizedBox(height: context.rh(8)),
          _AboutLinkRow(
            icon: LucideIcons.helpCircle,
            iconColor: AppTheme.mutedSteel,
            title: 'FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () => Navigator.of(context).pushNamed('/faq'),
          ),
          SizedBox(height: context.rh(24)),

          // Hidden 7-tap trigger on the version label: forces a test crash
          // to activate the Crashlytics dashboard (dev/diagnostics only).
          _CrashTestVersionText(),
        ],
      ),
    );
  }
}

class _CrashTestVersionText extends StatefulWidget {
  @override
  State<_CrashTestVersionText> createState() => _CrashTestVersionTextState();
}

class _CrashTestVersionTextState extends State<_CrashTestVersionText> {
  static const _tapsNeeded = 7;
  int _taps = 0;

  void _onTap() {
    _taps++;
    if (_taps < 3) return;
    if (_taps < _tapsNeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tapsNeeded - _taps} more taps to trigger test crash')),
      );
      return;
    }
    _taps = 0;
    if (Firebase.apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firebase not initialized — crash test unavailable')),
      );
      return;
    }
    // Official Crashlytics test-crash API: throws a fatal error that the
    // SDK records and reports on the next app launch.
    FirebaseCrashlytics.instance.crash();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: _onTap,
        child: Text('Version 1.0.0', style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
      ),
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AboutLinkRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: context.rAll(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.rr(8)),
              ),
              child: Icon(icon, color: iconColor, size: context.ri(18)),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: context.rsp(14), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                  Text(subtitle, style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: context.ri(18), color: AppTheme.mutedSteel),
          ],
        ),
      ),
    );
  }
}
