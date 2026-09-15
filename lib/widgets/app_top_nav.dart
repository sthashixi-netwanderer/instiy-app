import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../providers/providers.dart';

/// Horizontal top navigation bar shown on desktop (≥ 1024px).
/// Uses the same glassmorphism styling as AppBottomNav for visual consistency.
class AppTopNav extends ConsumerWidget {
  final int currentIndex;

  /// Shell mode — switch tabs locally instead of navigating. See
  /// [AdaptiveNav.onTabSelected].
  final ValueChanged<int>? onTabSelected;

  const AppTopNav({super.key, required this.currentIndex, this.onTabSelected});

  /// Tab tap inside the shell (if active) — otherwise the caller's callback.
  VoidCallback _tabTap(int index, VoidCallback fallback) {
    final select = onTabSelected;
    return select != null ? () => select(index) : fallback;
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool active,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? AppTheme.accent : AppTheme.mutedSteel,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.destructive,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? AppTheme.accent : AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final msgState = ref.watch(messageProvider);
    final unreadCount = msgState.unreadCount;
    final unreadExploreCount = msgState.unreadExploreNotificationsCount;
    final unreadServiceCount = msgState.unreadServiceNotificationsCount;
    final isAuth = authState.isAuthenticated;
    final isSeller = authState.user?.isSeller == true;
    // Dashboard hosts both the Selling and Services dashboards — visible
    // when opted in as either (see AppBottomNav).
    final isServiceProvider =
        ref.watch(serviceProvider).isServiceProvider == true;
    final showDash = isSeller || isServiceProvider;
    final isServicesTab = currentIndex == 2;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          inner: const ColorFilter.matrix(AppTheme.saturateMatrix),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.glassHeaderTop, AppTheme.glassHeaderBottom],
            ),
            border: Border(
              bottom: BorderSide(color: AppTheme.subtleBorder, width: 1.0),
            ),
            boxShadow: const [
              BoxShadow(
                color: AppTheme.glassHeaderShadow,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Brand
              Text(
                'Instiy',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 32),
              // Nav items
              if (isAuth) ...[
                _buildNavItem(
                  icon: LucideIcons.home,
                  label: 'Home',
                  active: currentIndex == 0,
                  onTap: _tabTap(
                    0,
                    () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/home', (route) => false),
                  ),
                ),
                _buildNavItem(
                  icon: LucideIcons.search,
                  label: 'Explore',
                  active: currentIndex == 1,
                  badgeCount: unreadExploreCount,
                  onTap: _tabTap(
                    1,
                    () => Navigator.of(context).pushNamed('/explore'),
                  ),
                ),
                _buildNavItem(
                  icon: LucideIcons.briefcaseBusiness,
                  label: 'Services',
                  active: currentIndex == 2,
                  badgeCount: unreadServiceCount,
                  onTap: _tabTap(
                    2,
                    () => Navigator.of(context).pushNamed('/services'),
                  ),
                ),
                if (!isServicesTab)
                  _buildNavItem(
                    icon: LucideIcons.video,
                    label: 'Clips',
                    active: currentIndex == 3,
                    onTap: _tabTap(
                      3,
                      () => Navigator.of(context).pushNamed('/clips'),
                    ),
                  ),
                _buildNavItem(
                  icon: LucideIcons.messageSquare,
                  label: 'Chats',
                  active: currentIndex == 4,
                  badgeCount: unreadCount,
                  onTap: _tabTap(
                    4,
                    () => Navigator.of(context).pushNamed('/messages'),
                  ),
                ),
                if (isSeller) ...[
                  _buildNavItem(
                    icon: LucideIcons.plus,
                    label: 'Sell',
                    active: false,
                    onTap: () => Navigator.of(context).pushNamed('/sell'),
                  ),
                ],
                if (showDash)
                  _buildNavItem(
                    icon: LucideIcons.layoutDashboard,
                    label: 'Dash',
                    active: currentIndex == 5,
                    onTap: _tabTap(
                      5,
                      () =>
                          Navigator.of(context).pushNamed('/seller-dashboard'),
                    ),
                  ),
              ] else ...[
                _buildNavItem(
                  icon: LucideIcons.home,
                  label: 'Home',
                  active: currentIndex == 0,
                  onTap: _tabTap(
                    0,
                    () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/home', (route) => false),
                  ),
                ),
                _buildNavItem(
                  icon: LucideIcons.search,
                  label: 'Explore',
                  active: currentIndex == 1,
                  onTap: _tabTap(
                    1,
                    () => Navigator.of(context).pushNamed('/explore'),
                  ),
                ),
                _buildNavItem(
                  icon: LucideIcons.briefcaseBusiness,
                  label: 'Services',
                  active: currentIndex == 2,
                  onTap: _tabTap(
                    2,
                    () => Navigator.of(context).pushNamed('/services'),
                  ),
                ),
                if (!isServicesTab)
                  _buildNavItem(
                    icon: LucideIcons.video,
                    label: 'Clips',
                    active: currentIndex == 3,
                    onTap: _tabTap(
                      3,
                      () => Navigator.of(context).pushNamed('/clips'),
                    ),
                  ),
                _buildNavItem(
                  icon: LucideIcons.info,
                  label: 'Info',
                  active: currentIndex == 4,
                  onTap: _tabTap(
                    4,
                    () => Navigator.of(context).pushNamed('/about-legal'),
                  ),
                ),
              ],
              const Spacer(),
              // Cart / bell / avatar would go here — reuse UserAvatarMenu
            ],
          ),
        ),
      ),
    );
  }
}
