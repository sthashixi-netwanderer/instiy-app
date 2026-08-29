import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'home/home_screen.dart';
import 'explore/explore_screen.dart';
import 'services/services_screen.dart';
import 'video/video_feed_screen.dart';
import 'messages/messages_screen.dart';
import 'seller/dashboard_screen.dart';
import 'info/about_legal_screen.dart' deferred as deferred_about_legal;

/// Persistent navigation shell. All main tabs live in an [IndexedStack], so
/// switching tabs (or pushing a detail screen and coming back) never rebuilds
/// a tab — scroll positions and loaded state survive until the app restarts
/// or the shell route is replaced.
///
/// Tab screens keep their own Scaffold + AdaptiveNav (only the active one is
/// visible); their nav switches tabs through [shellTabProvider] instead of
/// pushing routes.
class ShellScreen extends ConsumerStatefulWidget {
  final int initialTab;
  final String? exploreCategoryId;

  const ShellScreen({super.key, this.initialTab = 0, this.exploreCategoryId});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  /// Tabs that have been shown at least once. Unvisited tabs stay as empty
  /// placeholders so screens (and their network calls) only initialise on
  /// first visit.
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.initialTab.clamp(0, 5));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(shellTabProvider.notifier).state = widget.initialTab;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(shellTabProvider);
    // Mark visited after the frame so the IndexedStack children list stays
    // stable within a single build.
    if (!_visited.contains(tab)) {
      _visited.add(tab);
    }

    final auth = ref.watch(authProvider);
    final isAuth = auth.isAuthenticated;
    final isSeller = auth.user?.isSeller == true;

    final screens = <Widget>[
      const HomeScreen(),
      ExploreScreen(initialCategoryId: widget.exploreCategoryId),
      const ServicesScreen(),
      const VideoFeedScreen(),
      if (isAuth) const MessagesScreen() else const _DeferredAboutLegal(),
      if (isSeller) const SellerDashboardScreen() else const SizedBox.shrink(),
    ];

    return IndexedStack(
      index: tab.clamp(0, screens.length - 1),
      children: [
        for (var i = 0; i < screens.length; i++)
          _visited.contains(i) ? screens[i] : const SizedBox.shrink(),
      ],
    );
  }
}

/// Lazily loads the signed-out Info tab (same deferred library as the
/// /about-legal route).
class _DeferredAboutLegal extends StatefulWidget {
  const _DeferredAboutLegal();

  @override
  State<_DeferredAboutLegal> createState() => _DeferredAboutLegalState();
}

class _DeferredAboutLegalState extends State<_DeferredAboutLegal> {
  late final Future<void> _load = deferred_about_legal.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return deferred_about_legal.AboutLegalScreen();
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
