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
    this.resizeToAvoidBottomInset = false,
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

  @override
  Widget build(BuildContext context) {
    final maxWidth = _getMaxWidth(context);

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: backgroundColor,
      drawer: drawer,
      appBar: appBar,
      body: _wrapInCenteringConstraints(
        SafeArea(child: child),
        context,
        maxWidth: maxWidth,
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
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
