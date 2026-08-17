import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'app_bottom_nav.dart';
import 'app_top_nav.dart';

/// Returns the appropriate navigation widget based on screen size.
///
/// - Mobile (< 1024px): [AppBottomNav] (existing glassmorphism pill)
/// - Desktop (≥ 1024px): [AppTopNav] (horizontal top bar)
///
/// Usage in a screen:
/// ```dart
/// ResponsiveLayout(
///   bottomNavigationBar: AdaptiveNav(currentIndex: 0),
///   child: ...,
/// )
/// ```
class AdaptiveNav extends StatelessWidget {
  final int currentIndex;

  const AdaptiveNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) {
      return AppTopNav(currentIndex: currentIndex);
    }
    return AppBottomNav(currentIndex: currentIndex);
  }
}
