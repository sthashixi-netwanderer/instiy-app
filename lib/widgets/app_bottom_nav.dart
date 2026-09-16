import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../providers/providers.dart';

DateTime _lastTapTime = DateTime.now().subtract(const Duration(seconds: 1));

class AppBottomNav extends ConsumerWidget {
  final int currentIndex;

  /// Shell mode — switch tabs locally instead of navigating. See
  /// [AdaptiveNav.onTabSelected].
  final ValueChanged<int>? onTabSelected;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.onTabSelected,
  });

  void _handleNavTap(BuildContext context, bool isAuth, int index) {
    if (index == currentIndex) return;
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds < 300) return;
    _lastTapTime = now;

    // Shell mode: switch the persistent shell's tab — no route push, so
    // every tab keeps its scroll position and loaded state.
    final select = onTabSelected;
    if (select != null) {
      select(index);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (!isAuth) {
        switch (index) {
          case 0:
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/home', (route) => false);
            break;
          case 1:
            Navigator.of(context).pushNamed('/explore');
            break;
          case 2:
            Navigator.of(context).pushNamed('/services');
            break;
          case 3:
            Navigator.of(context).pushNamed('/clips');
            break;
          case 4:
            Navigator.of(context).pushNamed('/about-legal');
            break;
        }
        return;
      }
      switch (index) {
        case 0:
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/home', (route) => false);
          break;
        case 1:
          Navigator.of(context).pushNamed('/explore');
          break;
        case 2:
          Navigator.of(context).pushNamed('/services');
          break;
        case 3:
          Navigator.of(context).pushNamed('/clips');
          break;
        case 4:
          Navigator.of(context).pushNamed('/messages');
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
    String? svgAsset,
  }) {
    return _NavButton(
      icon: icon,
      svgAsset: svgAsset,
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
    final unreadCount = msgState.unreadCountExcludingMissed;
    final missedCallCount = msgState.missedCallCount;
    final unreadExploreCount = msgState.unreadExploreNotificationsCount;
    final isAuth = authState.isAuthenticated;
    final isSeller = authState.user?.isSeller == true;
    // Dashboard hosts both the Selling and Services dashboards — visible
    // when opted in as either. Watching the provider also constructs it,
    // which triggers the provider-status check for signed-in users.
    final isServiceProvider =
        ref.watch(serviceProvider).isServiceProvider == true;
    final showDash = isSeller || isServiceProvider;
    final isServicesTab = currentIndex == 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(
              sigmaX: AppTheme.glassBlurHeavy,
              sigmaY: AppTheme.glassBlurHeavy,
            ),
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
                          _navButton(
                            context,
                            isAuth,
                            0,
                            LucideIcons.home,
                            'Home',
                          ),
                          _navButton(
                            context,
                            isAuth,
                            1,
                            LucideIcons.search,
                            'Explore',
                            badgeCount: unreadExploreCount,
                          ),
                          _navButton(
                            context,
                            isAuth,
                            2,
                            LucideIcons.briefcaseBusiness,
                            'Services',
                          ),
                          if (!isServicesTab)
                            _navButton(
                              context,
                              isAuth,
                              3,
                              LucideIcons.video,
                              'Clips',
                            ),
                          _ChatsNavButton(
                            selected: currentIndex == 4,
                            unreadCount: unreadCount,
                            missedCount: missedCallCount,
                            svgAsset:
                                'assets/message-2-pending-svgrepo-com.svg',
                            onTap: () => _handleNavTap(context, isAuth, 4),
                          ),
                          if (showDash)
                            _navButton(
                              context,
                              isAuth,
                              5,
                              LucideIcons.layoutDashboard,
                              'Dash',
                            ),
                        ]
                      : [
                          _navButton(
                            context,
                            isAuth,
                            0,
                            LucideIcons.home,
                            'Home',
                          ),
                          _navButton(
                            context,
                            isAuth,
                            1,
                            LucideIcons.search,
                            'Explore',
                          ),
                          _navButton(
                            context,
                            isAuth,
                            2,
                            LucideIcons.briefcaseBusiness,
                            'Services',
                          ),
                          if (!isServicesTab)
                            _navButton(
                              context,
                              isAuth,
                              3,
                              LucideIcons.video,
                              'Clips',
                            ),
                          _navButton(
                            context,
                            isAuth,
                            4,
                            LucideIcons.info,
                            'Info',
                          ),
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
  final String? svgAsset;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    this.svgAsset,
    required this.label,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  /// Renders the custom SVG when one is provided, tinting it to match the
  /// [Icon] states; otherwise falls back to the material icon.
  Widget _buildIcon(Color color) {
    if (svgAsset != null) {
      return SvgPicture.asset(
        svgAsset!,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(icon, size: 20, color: color);
  }

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
            child: _buildIcon(Colors.white),
          )
        : SizedBox(
            width: 34,
            height: 34,
            child: Center(child: _buildIcon(AppTheme.mutedSteel)),
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
                if (!selected) ...[
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chats tab button that alternates between the chat icon and a phone
/// handset while there are unseen missed calls: chat phase carries the
/// unread-messages badge, caller phase carries the missed-call count.
/// The swap runs on a 5s loop for as long as [missedCount] is positive
/// and settles back on the chat icon once it clears. Chrome (34×34 slot,
/// selected gradient box, badge, label) mirrors [_NavButton].
class _ChatsNavButton extends StatefulWidget {
  final bool selected;
  final int unreadCount;
  final int missedCount;
  final String? svgAsset;
  final VoidCallback onTap;

  const _ChatsNavButton({
    required this.selected,
    required this.unreadCount,
    required this.missedCount,
    this.svgAsset,
    required this.onTap,
  });

  @override
  State<_ChatsNavButton> createState() => _ChatsNavButtonState();
}

class _ChatsNavButtonState extends State<_ChatsNavButton> {
  static const _switchInterval = Duration(seconds: 5);
  static const _switchDuration = Duration(milliseconds: 500);

  bool _showCaller = false;
  Timer? _switchTimer;

  @override
  void initState() {
    super.initState();
    _switchTimer = Timer.periodic(_switchInterval, (_) {
      if (!mounted) return;
      if (widget.missedCount > 0) {
        setState(() => _showCaller = !_showCaller);
      } else if (_showCaller) {
        setState(() => _showCaller = false);
      }
    });
  }

  @override
  void didUpdateWidget(_ChatsNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.missedCount == 0 && _showCaller) {
      setState(() => _showCaller = false);
    } else if (oldWidget.missedCount == 0 && widget.missedCount > 0) {
      // Fresh missed call — jump straight to the phone phase with the
      // counter instead of waiting up to 5s for the next loop tick.
      setState(() => _showCaller = true);
    }
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    super.dispose();
  }

  Widget _iconSlot(Widget icon) {
    if (widget.selected) {
      return Container(
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
        child: icon,
      );
    }
    return SizedBox(
      width: 34,
      height: 34,
      child: Center(child: icon),
    );
  }

  Widget _withBadge(Widget slot, int count) {
    if (count <= 0) return slot;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        slot,
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

  @override
  Widget build(BuildContext context) {
    // Phone phase only while missed calls exist; otherwise pinned on chat.
    final showPhone = widget.missedCount > 0 && _showCaller;

    final Widget iconArea = AnimatedSwitcher(
      duration: _switchDuration,
      transitionBuilder: (child, animation) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeInOut);
        return FadeTransition(
          opacity: curved,
          child:
              ScaleTransition(scale: curved, child: child),
        );
      },
      child: showPhone
          ? KeyedSubtree(
              key: const ValueKey('caller'),
              child: _withBadge(
                _iconSlot(
                  Icon(
                    LucideIcons.phone,
                    size: 20,
                    color: widget.selected
                        ? Colors.white
                        : AppTheme.mutedSteel,
                  ),
                ),
                widget.missedCount,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('chats'),
              child: _withBadge(
                _iconSlot(
                  widget.svgAsset != null
                      ? SvgPicture.asset(
                          widget.svgAsset!,
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                          colorFilter: ColorFilter.mode(
                            widget.selected
                                ? Colors.white
                                : AppTheme.mutedSteel,
                            BlendMode.srcIn,
                          ),
                        )
                      : Icon(
                          LucideIcons.messageSquare,
                          size: 20,
                          color: widget.selected
                              ? Colors.white
                              : AppTheme.mutedSteel,
                        ),
                ),
                widget.unreadCount,
              ),
            ),
    );

    return Expanded(
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: 'Chats',
        child: InkResponse(
          onTap: widget.onTap,
          radius: 34,
          child: SizedBox(
            height: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconArea,
                if (!widget.selected) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Chats',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
