import 'package:flutter/material.dart';
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

/// Header avatar button. Unauthenticated users are sent to login; signed-in
/// users open the account screen (`/account-menu`), which hosts the actions
/// that used to live in the avatar's popover dropdown.
class UserAvatarMenu extends StatelessWidget {
  final String? avatarUrl;
  final String? fullName;
  final String? businessName;
  final bool isVerified;
  final bool isAuthenticated;

  const UserAvatarMenu({
    super.key,
    this.avatarUrl,
    this.fullName,
    this.businessName,
    this.isVerified = false,
    this.isAuthenticated = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).pushNamed(isAuthenticated ? '/account-menu' : '/login'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ShadAvatar(
              isAuthenticated && avatarUrl?.isNotEmpty == true
                  ? avatarUrl
                  : null,
              size: const Size(36, 36),
              backgroundColor: AppTheme.accent,
              placeholder: isAuthenticated
                  ? Text(
                      (businessName ?? fullName ?? 'S')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : const Icon(LucideIcons.user, color: Colors.white, size: 18),
            ),
            if (isAuthenticated && isVerified)
              const Positioned(
                bottom: -2,
                right: -2,
                child: VerificationBadge(size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
