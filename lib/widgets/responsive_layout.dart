import 'package:flutter/material.dart';
import '../config/app_theme.dart';

enum ResponsiveLayoutType {
  general, // E.g., Home, Explore, Product list
  form,    // E.g., Auth screens, edit screens, where components should be tightly centered
  detail,  // E.g., Product details
}

class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  final ResponsiveLayoutType type;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color backgroundColor;
  final ScrollController? scrollController;
  final Widget? drawer;
  final bool resizeToAvoidBottomInset;

  /// When true, paints the vibrant ambient gradient + colour blobs behind the
  /// body so frosted-glass surfaces have something colourful to refract. Set
  /// to false for screens that need a plain background (e.g. media viewers).
  final bool ambientBackground;
  final bool extendBodyBehindAppBar;

  /// Optional top navigation bar for desktop (≥ 1024px). When provided,
  /// replaces the [bottomNavigationBar] on desktop screens.
  final Widget? topNav;

  const ResponsiveLayout({
    super.key,
    required this.child,
    this.type = ResponsiveLayoutType.general,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor = AppTheme.canvasWhite,
    this.scrollController,
    this.drawer,
    this.resizeToAvoidBottomInset = true,
    this.ambientBackground = true,
    this.extendBodyBehindAppBar = false,
    this.topNav,
  });

  double _getMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return double.infinity; // Mobile: full width

    switch (type) {
      case ResponsiveLayoutType.form:
        return 480.0; // Forms: compact & elegant
      case ResponsiveLayoutType.detail:
        return 900.0; // Detail: balanced width
      case ResponsiveLayoutType.general:
        return 1200.0; // General list: spacious grid/sections
    }
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  @override
  Widget build(BuildContext context) {
    final maxWidth = _getMaxWidth(context);
    final isDesktop = _isDesktop(context);

    // On desktop with topNav, use a row layout: [topNav] + [constrained body].
    // On mobile/tablet, use the traditional Scaffold with optional bottom nav.
    if (isDesktop && topNav != null) {
      return Scaffold(
        backgroundColor: ambientBackground ? Colors.transparent : backgroundColor,
        body: Column(
          children: [
            topNav!,
            Expanded(
              child: ambientBackground
                  ? AppTheme.ambientBackground(child: _buildBody(context, maxWidth))
                  : _buildBody(context, maxWidth),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    final body = _wrapInCenteringConstraints(
      SafeArea(
        bottom: bottomNavigationBar == null,
        top: !extendBodyBehindAppBar,
        child: child,
      ),
      context,
      maxWidth: maxWidth,
    );

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: ambientBackground ? Colors.transparent : backgroundColor,
      extendBody: bottomNavigationBar != null,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      drawer: drawer,
      appBar: appBar,
      body: ambientBackground ? AppTheme.ambientBackground(child: body) : body,
      bottomNavigationBar: bottomNavigationBar != null
          ? _ConstrainedBottomNav(
              maxWidth: maxWidth,
              child: bottomNavigationBar!,
            )
          : null,
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildBody(BuildContext context, double maxWidth) {
    return _wrapInCenteringConstraints(
      SafeArea(
        top: !extendBodyBehindAppBar,
        child: child,
      ),
      context,
      maxWidth: maxWidth,
    );
  }

  Widget _wrapInCenteringConstraints(
    Widget widget,
    BuildContext context, {
    required double maxWidth,
  }) {
    if (maxWidth == double.infinity) return widget;

    if (widget is PreferredSizeWidget) {
      return _PreferredSizeResponsive(
        preferredSizeWidget: widget,
        maxWidth: maxWidth,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: widget,
      ),
    );
  }
}

/// Constrains the bottom navigation bar to the content max-width
/// so it doesn't stretch across the full screen on tablet/desktop.
class _ConstrainedBottomNav extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const _ConstrainedBottomNav({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class _PreferredSizeResponsive extends StatelessWidget implements PreferredSizeWidget {
  final PreferredSizeWidget preferredSizeWidget;
  final double maxWidth;

  const _PreferredSizeResponsive({
    required this.preferredSizeWidget,
    required this.maxWidth,
  });

  @override
  Size get preferredSize => preferredSizeWidget.preferredSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: preferredSizeWidget,
      ),
    );
  }
}
