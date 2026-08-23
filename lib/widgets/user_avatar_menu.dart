import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import 'verification_badge.dart';

/// Generic icon button with a count badge (cart, bell, etc.)
///
/// The badge mirrors the app bottom navigation's unread badge exactly —
/// same pill metrics, same corner offset — so badge buttons look identical
/// wherever they appear.
class BadgeIconButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color activeColor;
  final VoidCallback onPressed;

  const BadgeIconButton({
    super.key,
    required this.icon,
    required this.count,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ShadIconButton.ghost(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: count > 0 ? activeColor : AppTheme.mutedSteel),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.destructive,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: onPressed,
    );
  }
}

/// Reusable avatar with popover dropdown menu.
/// Shows a user icon for unauthenticated users, or the profile avatar
/// with a popover menu (Wishlist, Orders, Wallet, Following, Settings, Sign Out) when authenticated.
class UserAvatarMenu extends ConsumerStatefulWidget {
  final String? avatarUrl;
  final String? fullName;
  final String? businessName;
  final bool isVerified;
  final bool isAuthenticated;
  final VoidCallback onLoginTap;
  final VoidCallback onWishlistTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onWalletTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onSignOut;

  const UserAvatarMenu({
    super.key,
    this.avatarUrl,
    this.fullName,
    this.businessName,
    this.isVerified = false,
    this.isAuthenticated = false,
    required this.onLoginTap,
    required this.onWishlistTap,
    required this.onOrdersTap,
    required this.onWalletTap,
    required this.onFollowingTap,
    required this.onSettingsTap,
    required this.onSignOut,
  });

  @override
  ConsumerState<UserAvatarMenu> createState() => _UserAvatarMenuState();
}

class _UserAvatarMenuState extends ConsumerState<UserAvatarMenu> {
  final _popoverController = ShadPopoverController();

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final theme = ShadTheme.of(context);
    final textColor = destructive ? AppTheme.destructive : theme.colorScheme.popoverForeground;
    final iconColor = destructive ? AppTheme.destructive : theme.colorScheme.mutedForeground;

    return InkWell(
      onTap: () {
        _popoverController.hide();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAuthenticated) {
      return GestureDetector(
        onTap: widget.onLoginTap,
        child: ShadAvatar(
          null,
          size: const Size(36, 36),
          backgroundColor: AppTheme.accent,
          placeholder: const Icon(LucideIcons.user, color: Colors.white, size: 18),
        ),
      );
    }

    return ShadPopover(
      controller: _popoverController,
      anchor: const ShadAnchor(
        childAlignment: Alignment.topRight,
        overlayAlignment: Alignment.bottomRight,
        offset: Offset(0, 8),
      ),
      padding: const EdgeInsets.all(8),
      popover: (context) => SizedBox(
        width: 140,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMenuItem(
              icon: LucideIcons.heart,
              label: 'Wishlist',
              onTap: widget.onWishlistTap,
            ),
            _buildMenuItem(
              icon: LucideIcons.shoppingBag,
              label: 'My Orders',
              onTap: widget.onOrdersTap,
            ),
            _buildMenuItem(
              icon: LucideIcons.wallet,
              label: 'Wallet',
              onTap: widget.onWalletTap,
            ),
            _buildMenuItem(
              icon: LucideIcons.users,
              label: 'Following',
              onTap: widget.onFollowingTap,
            ),
            _buildMenuItem(
              icon: LucideIcons.settings,
              label: 'Settings',
              onTap: widget.onSettingsTap,
            ),
            InkWell(
              onTap: () {
                AppTheme.showGlassDialog(
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
                ).then((confirmed) {
                  _popoverController.hide();
                  if (confirmed == true) widget.onSignOut();
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.logOut, size: 18, color: AppTheme.destructive),
                    const SizedBox(width: 12),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.destructive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: _popoverController.toggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ShadAvatar(
                widget.avatarUrl?.isNotEmpty == true ? widget.avatarUrl : null,
                size: const Size(36, 36),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (widget.businessName ?? widget.fullName ?? 'S')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.isVerified)
                const Positioned(
                  bottom: -2,
                  right: -2,
                  child: VerificationBadge(size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
