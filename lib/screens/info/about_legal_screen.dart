import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';

class AboutLegalScreen extends StatelessWidget {
  const AboutLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('About & Legal')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 16, 16),
        children: [
          // App info
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    LucideIcons.shoppingBag,
                    size: 36,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Instiy',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Campus Marketplace',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.mutedSteel,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // About section
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'About',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.mutedSteel,
              ),
            ),
          ),
          _LinkRow(
            icon: LucideIcons.info,
            title: 'About Instiy',
            subtitle: 'Learn more about the platform',
            onTap: () => Navigator.of(context).pushNamed('/about'),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            icon: LucideIcons.helpCircle,
            title: 'FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () => Navigator.of(context).pushNamed('/faq'),
          ),
          const SizedBox(height: 24),

          // Legal section
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Legal',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.mutedSteel,
              ),
            ),
          ),
          _LinkRow(
            icon: LucideIcons.shield,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            icon: LucideIcons.fileText,
            title: 'Terms & Conditions',
            subtitle: 'Rules for using Instiy',
            onTap: () => Navigator.of(context).pushNamed('/terms-conditions'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: AppTheme.mutedSteel,
            ),
          ],
        ),
      ),
    );
  }
}
