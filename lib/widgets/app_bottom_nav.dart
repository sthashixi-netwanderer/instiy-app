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

  void _handleNavTap(BuildContext context, bool isAuth, int index) {
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
  }

  Widget _navButton(
    BuildContext context,
    bool isAuth,
    int index,
    IconData icon,
    String label, {
    int badgeCount = 0,
  }) {
    return _NavButton(
      icon: icon,
      label: label,
      selected: currentIndex == index,
      badgeCount: badgeCount,
      onTap: () => _handleNavTap(context, isAuth, index),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: isAuth
                      ? [
                          _navButton(context, isAuth, 0, LucideIcons.home, 'Home'),
                          _navButton(context, isAuth, 1, LucideIcons.search, 'Explore'),
                          _navButton(context, isAuth, 2, LucideIcons.video, 'Clips'),
                          _navButton(context, isAuth, 3, LucideIcons.messageSquare, 'Messages', badgeCount: unreadCount),
                          _navButton(context, isAuth, 4, LucideIcons.plus, 'Sell'),
                          _navButton(context, isAuth, 5, LucideIcons.layoutDashboard, 'Dashboard'),
                        ]
                      : [
                          _navButton(context, isAuth, 0, LucideIcons.home, 'Home'),
                          _navButton(context, isAuth, 1, LucideIcons.search, 'Explore'),
                          _navButton(context, isAuth, 2, LucideIcons.video, 'Clips'),
                          _navButton(context, isAuth, 3, LucideIcons.plus, 'Sell'),
                          _navButton(context, isAuth, 4, LucideIcons.info, 'Info'),
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single nav button. The icon sits in a fixed 34×34 slot (so swapping to
/// the selected gradient box never shifts the layout) with the label centered
/// beneath — the column is centered both vertically and horizontally.
class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget iconSlot = selected
        ? Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.accentBright, AppTheme.accent],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          )
        : SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Icon(icon, size: 20, color: AppTheme.mutedSteel),
            ),
          );

    final Widget iconArea = badgeCount > 0
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              iconSlot,
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.destructive,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  alignment: Alignment.center,
                  child: Text(
                    '$badgeCount',
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
          )
        : iconSlot;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: SizedBox(
            height: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconArea,
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTheme.accent : AppTheme.mutedSteel,
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
