import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../providers/providers.dart';

DateTime _lastTapTime = DateTime.now().subtract(const Duration(seconds: 1));

class AppBottomNav extends ConsumerWidget {
  final int currentIndex;

  const AppBottomNav({super.key, required this.currentIndex});

  Widget _buildActiveIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accentBright, AppTheme.accent],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildBadgeIcon(IconData icon, int count, {bool active = false}) {
    final iconWidget = active ? _buildActiveIcon(icon) : Icon(icon);
    if (count <= 0) return iconWidget;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        Positioned(
          right: active ? -2 : -8,
          top: active ? -4 : -4,
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
    );
  }

  BottomNavigationBarItem _navItem(IconData icon, String label, {int badgeCount = 0}) {
    return BottomNavigationBarItem(
      icon: badgeCount > 0
          ? _buildBadgeIcon(icon, badgeCount)
          : Icon(icon),
      activeIcon: badgeCount > 0
          ? _buildBadgeIcon(icon, badgeCount, active: true)
          : _buildActiveIcon(icon),
      label: label,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final msgState = ref.watch(messageProvider);
    final unreadCount = msgState.unreadCount;
    final isAuth = authState.isAuthenticated;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(
                sigmaX: AppTheme.glassBlurHeavy, sigmaY: AppTheme.glassBlurHeavy),
            inner: const ColorFilter.matrix(AppTheme.saturateMatrix),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.glassHeaderTop, AppTheme.glassHeaderBottom],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.subtleBorder, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.glassHeaderShadow,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BottomNavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
      currentIndex: currentIndex,
      onTap: (index) {
        if (index == currentIndex) return;
        final now = DateTime.now();
        if (now.difference(_lastTapTime).inMilliseconds < 300) return;
        _lastTapTime = now;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (!isAuth) {
            switch (index) {
              case 0:
                Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                break;
              case 1:
                Navigator.of(context).pushNamed('/explore');
                break;
              case 2:
                Navigator.of(context).pushNamed('/clips');
                break;
              case 3:
                Navigator.of(context).pushNamed('/login');
                break;
              case 4:
                Navigator.of(context).pushNamed('/about-legal');
                break;
            }
            return;
          }
          switch (index) {
            case 0:
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
              break;
            case 1:
              Navigator.of(context).pushNamed('/explore');
              break;
            case 2:
              Navigator.of(context).pushNamed('/clips');
              break;
            case 3:
              Navigator.of(context).pushNamed('/messages');
              break;
            case 4:
              Navigator.of(context).pushNamed('/sell');
              break;
            case 5:
              Navigator.of(context).pushNamed('/seller-dashboard');
              break;
          }
        });
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppTheme.accent,
      unselectedItemColor: AppTheme.mutedSteel,
      showUnselectedLabels: true,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      items: isAuth
          ? [
              _navItem(LucideIcons.home, 'Home'),
              _navItem(LucideIcons.search, 'Explore'),
              _navItem(LucideIcons.video, 'Clips'),
              _navItem(LucideIcons.messageSquare, 'Messages', badgeCount: unreadCount),
              _navItem(LucideIcons.plus, 'Sell'),
              _navItem(LucideIcons.layoutDashboard, 'Dashboard'),
            ]
          : [
              _navItem(LucideIcons.home, 'Home'),
              _navItem(LucideIcons.search, 'Explore'),
              _navItem(LucideIcons.video, 'Clips'),
              _navItem(LucideIcons.plus, 'Sell'),
              _navItem(LucideIcons.info, 'Info'),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
