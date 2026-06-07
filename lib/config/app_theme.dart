import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppTheme {
  // Design System Colors
  static const canvasWhite = Color(0xFFFAFAF9);
  static const pureSurface = Color(0xFFFFFFFF);
  static const charcoalInk = Color(0xFF1C1917);
  static const mutedSteel = Color(0xFF78716C);
  static const whisperBorder = Color(0xFFE7E5E4);
  static const warmMist = Color(0xFFF5F5F4);
  static const accent = Color(0xFF6c47ff);
  static const successMoss = Color(0xFF4D7C59);
  static const warningAmber = Color(0xFFD97706);
  static const destructive = Color(0xFFDC2626);

  // Text Colors
  static const textPrimary = charcoalInk;
  static const textSecondary = mutedSteel;
  static const textTertiary = Color(0xFFA8A29E);

  // Glassmorphism Tokens
  // Warm tinted glass — visible on white canvas
  static const glassSurface = Color(0xF0F5F2EF); // warm stone 94%
  static const glassSurfaceLight = Color(0xE6F5F2EF); // warm stone 90%
  static const glassSurfaceHeavy = Color(0xF7F5F2EF); // warm stone 97%
  static const glassBorder = Color(0x59C8C0B8); // warm stone 35%
  static const glassBorderLight = Color(0x3DC8C0B8); // warm stone 24%
  static const glassShadow = Color(0x14000000); // black 8%
  static const double glassBlur = 20.0;
  static const double glassBlurLight = 12.0;
  static const double glassBlurHeavy = 30.0;

  /// Glass container decoration (no blur — use with BackdropFilter for frosted effect)
  static BoxDecoration glassDecoration({
    double radius = 16,
    Color? color,
    Border? border,
  }) {
    return BoxDecoration(
      color: color ?? glassSurface,
      borderRadius: BorderRadius.circular(radius),
      border: border ?? Border.all(color: glassBorder, width: 0.5),
      boxShadow: const [
        BoxShadow(
          color: glassShadow,
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  /// Wrap a widget with frosted glass effect (ClipRRect + BackdropFilter)
  static Widget frosted({
    required Widget child,
    double sigmaX = glassBlur,
    double sigmaY = glassBlur,
    double radius = 16,
    Color? color,
    Border? border,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
        child: Container(
          decoration: glassDecoration(radius: radius, color: color, border: border),
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  /// Returns an AppBar with frosted glass background
  static AppBar glassAppBar({
    required BuildContext context,
    Widget? title,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: bottom,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
          child: Container(
            decoration: const BoxDecoration(
              color: glassSurface,
              border: Border(
                bottom: BorderSide(color: glassBorder, width: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Category Colors
  static const categoryColors = [
    0xFF6c47ff,
    0xFF8B5CF6,
    0xFFEC4899,
    0xFFD97706,
    0xFF4D7C59,
    0xFF3B82F6,
    0xFFDC2626,
    0xFF14B8A6,
  ];

  static ShadThemeData get lightTheme {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadStoneColorScheme.light(
        primary: accent,
        primaryForeground: Colors.white,
        destructive: destructive,
        destructiveForeground: Colors.white,
      ),
    );
  }

  static ShadThemeData get darkTheme {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadStoneColorScheme.dark(
        primary: accent,
        primaryForeground: Colors.white,
        destructive: destructive,
        destructiveForeground: Colors.white,
      ),
    );
  }

  /// Shows a glassmorphism-styled dialog with constrained width and rounded corners.
  /// Use [title]/[description]/[child]/[actions] for simple dialogs,
  /// or [builder] for complex dialogs that need StatefulBuilder etc.
  static Future<T?> showGlassDialog<T>({
    required BuildContext context,
    Widget? title,
    Widget? description,
    Widget? child,
    List<Widget>? actions,
    Widget Function(BuildContext ctx)? builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black38,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
              child: Container(
                decoration: glassDecoration(radius: 20),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: builder != null
                    ? builder(ctx)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            DefaultTextStyle(
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: charcoalInk,
                              ),
                              child: title,
                            ),
                          if (description != null) ...[
                            const SizedBox(height: 8),
                            DefaultTextStyle(
                              style: const TextStyle(
                                fontSize: 14,
                                color: mutedSteel,
                                height: 1.4,
                              ),
                              child: description,
                            ),
                          ],
                          if (child != null) ...[
                            const SizedBox(height: 16),
                            child,
                          ],
                          if (actions != null && actions.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                for (int i = 0; i < actions.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  actions[i],
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Custom page transition: fade + subtle slide up
  static Route<T> fadeSlideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween<Offset>(
          begin: const Offset(0.0, 0.05),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: animation.drive(tween),
            child: child,
          ),
        );
      },
    );
  }
}
