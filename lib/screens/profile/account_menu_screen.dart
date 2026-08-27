import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_press.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/responsive_layout.dart';

/// Account hub opened from the header avatar — the actions that used to live
/// in the avatar's popover dropdown, presented as a full screen.
class AccountMenuScreen extends ConsumerStatefulWidget {
  const AccountMenuScreen({super.key});

  @override
  ConsumerState<AccountMenuScreen> createState() => _AccountMenuScreenState();
}

class _AccountMenuScreenState extends ConsumerState<AccountMenuScreen> {
  String? _businessName;

  @override
  void initState() {
    super.initState();
    _loadBusinessName();
  }

  Future<void> _loadBusinessName() async {
    try {
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid == null) return;
      final data = await SupabaseService.table(
        'business_profiles',
      ).select('business_name').eq('seller_id', uid).maybeSingle();
      if (mounted && data != null) {
        setState(() => _businessName = data['business_name'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Sign Out'),
      description: const Text('Are you sure you want to sign out?'),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign Out'),
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await ref.read(authProvider).signOut();
      if (mounted) {
        unawaited(
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
        );
      }
    }
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    final color = highlight ? AppTheme.accent : AppTheme.mutedSteel;
    return AnimatedPress(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: EdgeInsets.symmetric(horizontal: context.rw(14)),
        decoration: highlight
            ? BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(context.rr(12)),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.3),
                ),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, size: context.ri(19), color: color),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: context.rsp(14.5),
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final isSeller = user?.isSeller == true;
    final displayName = _businessName ?? user?.fullName ?? 'Account';

    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Account'),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          context.rw(16),
          MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(12),
          context.rw(16),
          context.rh(120),
        ),
        children: [
          // Profile summary card with inline edit button
          ClipRRect(
            borderRadius: BorderRadius.circular(context.rr(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppTheme.glassBlurLight,
                sigmaY: AppTheme.glassBlurLight,
              ),
              child: Container(
                decoration: AppTheme.glassDecoration(radius: context.rr(20)),
                padding: context.rAll(18),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ShadAvatar(
                          user?.avatarUrl?.isNotEmpty == true
                              ? user!.avatarUrl
                              : null,
                          size: Size(context.ri(56), context.ri(56)),
                          backgroundColor: AppTheme.accent,
                          placeholder: Text(
                            displayName[0].toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: context.rsp(20),
                            ),
                          ),
                        ),
                        if (user?.isVerified == true)
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: VerificationBadge(size: context.ri(16)),
                          ),
                      ],
                    ),
                    SizedBox(width: context.rw(14)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'Signed in',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: context.rsp(16),
                              fontWeight: FontWeight.w700,
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          if (_businessName != null) ...[
                            SizedBox(height: context.rh(2)),
                            Text(
                              _businessName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: context.rsp(13),
                                fontWeight: FontWeight.w500,
                                color: AppTheme.accent,
                              ),
                            ),
                          ],
                          if (isSeller) ...[
                            SizedBox(height: context.rh(2)),
                            Text(
                              'Seller account',
                              style: TextStyle(
                                fontSize: context.rsp(12),
                                color: AppTheme.mutedSteel,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: context.rw(10)),
                    AnimatedPress(
                      onTap: () =>
                          Navigator.of(context).pushNamed('/edit-profile'),
                      child: Container(
                        width: context.rw(38),
                        height: context.rw(38),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(context.rr(12)),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          LucideIcons.penLine,
                          size: context.ri(17),
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: context.rh(16)),
          // Seller verification — standout CTA, hidden once the account
          // is verified.
          if (user?.isVerified != true) ...[
            // Seller verification — standout CTA
            AnimatedPress(
              onTap: () => Navigator.of(
                context,
              ).pushNamed('/seller-profile-verification'),
              child: Container(
                padding: context.rPadding(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent,
                      AppTheme.accent.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(context.rr(18)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: context.ri(22),
                      color: Colors.white,
                    ),
                    SizedBox(width: context.rw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seller Verification',
                            style: TextStyle(
                              fontSize: context.rsp(15),
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: context.rh(1)),
                          Text(
                            'Verify your identity to start selling',
                            style: TextStyle(
                              fontSize: context.rsp(12),
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: context.rh(16)),
          // Actions — the former avatar dropdown items
          ClipRRect(
            borderRadius: BorderRadius.circular(context.rr(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppTheme.glassBlurLight,
                sigmaY: AppTheme.glassBlurLight,
              ),
              child: Container(
                decoration: AppTheme.glassDecoration(radius: context.rr(20)),
                padding: context.rAll(8),
                child: Column(
                  children: [
                    _buildMenuRow(
                      icon: LucideIcons.heart,
                      label: 'Wishlist',
                      onTap: () => Navigator.of(context).pushNamed('/wishlist'),
                    ),
                    Divider(
                      height: 1,
                      indent: context.rw(44),
                      endIndent: context.rw(12),
                      color: AppTheme.whisperBorder.withValues(alpha: 0.6),
                    ),
                    _buildMenuRow(
                      icon: LucideIcons.shoppingBag,
                      label: 'My Orders',
                      onTap: () => Navigator.of(context).pushNamed('/orders'),
                    ),
                    Divider(
                      height: 1,
                      indent: context.rw(44),
                      endIndent: context.rw(12),
                      color: AppTheme.whisperBorder.withValues(alpha: 0.6),
                    ),
                    _buildMenuRow(
                      icon: LucideIcons.wallet,
                      label: 'Wallet',
                      onTap: () => Navigator.of(context).pushNamed('/wallet'),
                    ),
                    Divider(
                      height: 1,
                      indent: context.rw(44),
                      endIndent: context.rw(12),
                      color: AppTheme.whisperBorder.withValues(alpha: 0.6),
                    ),
                    _buildMenuRow(
                      icon: LucideIcons.users,
                      label: 'Following',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/following'),
                    ),
                    if (!isSeller) ...[
                      SizedBox(height: context.rh(8)),
                      _buildMenuRow(
                        icon: LucideIcons.store,
                        label: 'Become a Seller',
                        onTap: () =>
                            Navigator.of(context).pushNamed('/become-seller'),
                        highlight: true,
                      ),
                    ],
                    SizedBox(height: context.rh(8)),
                    _buildMenuRow(
                      icon: LucideIcons.settings,
                      label: 'Settings',
                      onTap: () => Navigator.of(context).pushNamed('/account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: context.rh(24)),
          // Sign out — centered on its own
          Center(
            child: ShadButton.destructive(
              onPressed: _confirmSignOut,
              leading: Icon(LucideIcons.logOut, size: context.ri(18)),
              child: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }
}
