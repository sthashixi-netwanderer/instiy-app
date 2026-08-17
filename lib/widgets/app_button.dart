import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';

/// A shared primary button that caps its width on tablet/desktop.
///
/// On mobile (< 600px), fills the parent (full-width, same as today).
/// On tablet/desktop (≥ 600px), centers itself and caps at [maxWidth].
/// This directly fixes the "buttons too long on desktop" complaint.
///
/// Use `block: true` for full-bleed CTAs that should stay full-width
/// (e.g. checkout "Pay Now" button).
class AppButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double maxWidth;
  final bool block;
  final bool loading;
  final bool outline;
  final bool ghost;
  final bool link;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final bool expanded;

  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.maxWidth = 400,
    this.block = false,
    this.loading = false,
    this.outline = false,
    this.ghost = false,
    this.link = false,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.trailing,
    this.padding,
    this.height,
    this.expanded = true,
  });

  const AppButton.outline({
    super.key,
    required this.onPressed,
    required this.child,
    this.maxWidth = 400,
    this.block = false,
    this.loading = false,
    this.ghost = false,
    this.link = false,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.trailing,
    this.padding,
    this.height,
    this.expanded = true,
  }) : outline = true;

  const AppButton.ghost({
    super.key,
    required this.onPressed,
    required this.child,
    this.maxWidth = 400,
    this.block = false,
    this.loading = false,
    this.outline = false,
    this.link = false,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.trailing,
    this.padding,
    this.height,
    this.expanded = true,
  }) : ghost = true;

  const AppButton.link({
    super.key,
    required this.onPressed,
    required this.child,
    this.maxWidth = 400,
    this.block = false,
    this.loading = false,
    this.outline = false,
    this.ghost = false,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.trailing,
    this.padding,
    this.height,
    this.expanded = false,
  }) : link = true;

  @override
  Widget build(BuildContext context) {
    final isWide = context.screenWidth >= 600;
    final shouldCap = isWide && !block && !link;

    final button = _buildButton(context);

    if (link) return button;

    final wrapped = SizedBox(
      width: block || (!shouldCap && expanded) ? double.infinity : null,
      height: height ?? context.rh(50),
      child: button,
    );

    if (!shouldCap) return wrapped;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: wrapped,
      ),
    );
  }

  Widget _buildButton(BuildContext context) {
    if (outline) {
      return ShadButton.outline(
        onPressed: loading ? null : onPressed,
        leading: leading,
        trailing: trailing,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: padding,
        child: child,
      );
    }
    if (ghost) {
      return ShadButton.ghost(
        onPressed: loading ? null : onPressed,
        leading: leading,
        trailing: trailing,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: padding,
        child: child,
      );
    }
    if (link) {
      return ShadButton.link(
        onPressed: loading ? null : onPressed,
        child: child,
      );
    }
    return ShadButton(
      onPressed: loading ? null : onPressed,
      leading: leading,
      trailing: trailing,
      backgroundColor: backgroundColor ?? AppTheme.accent,
      foregroundColor: foregroundColor ?? Colors.white,
      padding: padding,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : child,
    );
  }
}
