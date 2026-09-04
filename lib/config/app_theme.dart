import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
// shadcn_ui re-exports flutter_animate but hides the `Effect` base type, so we
// import it directly to type the shared dropdown animation list.
import 'package:flutter_animate/flutter_animate.dart' show Effect;

class AppTheme {
  static Color? parseHexColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    try {
      final hex = hexString.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return null;
  }
  // ─────────────────────────────────────────────────────────────────────────
  // Design System Colors — "Trust Purple" marketplace palette
  // (UI/UX Pro Max: Marketplace P2P — trust purple + transaction green)
  // Light & vibrant so frosted glass POPS against a colourful base.
  // Text colours are deliberately OFF the background hue (deep violet ink on a
  // pale lilac canvas) for strong contrast.
  // ─────────────────────────────────────────────────────────────────────────

  // Vibrant, slightly tinted canvas so backdrop-blur has colour to refract.
  static const canvasWhite = Color(0xFFFAF5FF); // pale lilac
  static const pureSurface = Color(0xFFFFFFFF);

  // ─────────────────────────────────────────────────────────────────────────
  // Generic Clean Background — for screens that don't need glassmorphism.
  // Pure white / off-white surfaces with subtle borders ensure maximum
  // readability for all content (text, cards, forms) without visual noise.
  // ─────────────────────────────────────────────────────────────────────────
  static const cleanBackground = Color(0xFFFFFFFF); // pure white
  static const cleanBackgroundAlt = Color(0xFFFAFAFA); // off-white for subtle sections
  static const subtleBorder = Color(0xFFE5E5E5); // light grey border/divider

  // Frosted surfaces that float ABOVE the clean white background. A touch
  // darker and cooler than pure white so bars and cards separate from the
  // page while the backdrop blur keeps the glass feel (iOS light style).
  static const glassHeaderTop = Color(0xF7FAFBFC); // 97% near-white (gradient top)
  static const glassHeaderBottom = Color(0xE9F2F3F5); // 91% cool light grey (gradient bottom)
  static const glassHeaderShadow = Color(0x14202A43); // slate-tinted 8% (soft lift)
  static const headerBarSolid = Color(0xFFF4F5F7); // opaque bar for collapsed sliver headers

  // Ink / text — deep violet, never the same hue/lightness as the canvas.
  static const charcoalInk = Color(0xFF3B0764); // deep violet ink (primary text)
  static const mutedSteel = Color(0xFF6D5B8A); // muted violet-grey (secondary)
  static const whisperBorder = Color(0xFFE9D5FF); // soft lilac border
  static const warmMist = Color(0xFFF1E9FB); // lilac mist (placeholders/skeleton)

  // Brand & semantic
  static const accent = Color(0xFF7C3AED); // trust purple
  static const accentBright = Color(0xFF9F67FF); // lighter glow purple
  static const successMoss = Color(0xFF16A34A); // transaction green
  static const warningAmber = Color(0xFFD97706);
  static const destructive = Color(0xFFDC2626);

  // Ambient blob colours used behind glass to make it shimmer.
  static const blobViolet = Color(0xFF8B5CF6);
  static const blobPink = Color(0xFFEC4899);
  static const blobBlue = Color(0xFF3B82F6);

  // Text Colors
  static const textPrimary = charcoalInk;
  static const textSecondary = mutedSteel;
  static const textTertiary = Color(0xFF9A82C0);

  // ─────────────────────────────────────────────────────────────────────────
  // Glassmorphism Tokens — TRANSLUCENT frosted glass (pops, not opaque)
  // Per UI/UX Pro Max glassmorphism spec: translucent white 15-30% opacity,
  // backdrop blur 10-20px, light-source border. Lower opacity + higher blur =
  // the glass actually reads as glass over the vibrant canvas.
  // ─────────────────────────────────────────────────────────────────────────
  static const glassSurface = Color(0x40FFFFFF); // white 25%
  static const glassSurfaceLight = Color(0x2EFFFFFF); // white 18%
  static const glassSurfaceHeavy = Color(0x59FFFFFF); // white 35% (nav/app bar)
  static const glassBorder = Color(0x66FFFFFF); // white 40% — bright edge
  static const glassBorderLight = Color(0x40FFFFFF); // white 25%
  static const glassHighlight = Color(0x80FFFFFF); // top light-source highlight
  static const glassShadow = Color(0x1F4C1D95); // violet-tinted shadow 12%
  static const double glassBlur = 22.0;
  static const double glassBlurLight = 14.0;
  static const double glassBlurHeavy = 32.0;

  /// Web-optimized blur sigma. On web, slightly lower sigma for smoother
  /// rendering across browsers while maintaining the frosted-glass look.
  static double get webGlassBlur => kIsWeb ? 18.0 : glassBlur;
  static double get webGlassBlurLight => kIsWeb ? 10.0 : glassBlurLight;
  static double get webGlassBlurHeavy => kIsWeb ? 22.0 : glassBlurHeavy;

  /// A vibrant ambient background to sit BEHIND frosted glass so the blur has
  /// colour to refract. Use as the body of glass-heavy screens.
  static Widget ambientBackground({required Widget child}) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFAF5FF),
                          Color(0xFFF3E8FF),
                          Color(0xFFFDF2F8),
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                // Soft colour blobs — they show through the glass blur.
                Positioned(top: -80, left: -60, child: _blob(blobViolet, 240)),
                Positioned(top: 140, right: -90, child: _blob(blobPink, 200)),
                Positioned(bottom: -100, left: -40, child: _blob(blobBlue, 260)),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }

  /// Simple, clean background — solid color with no gradient, blobs, or glass.
  /// Use for screens that prioritize readability over glassmorphism aesthetics.
  static Widget cleanBackgroundWidget({required Widget child, Color? color}) {
    return ColoredBox(
      color: color ?? cleanBackground,
      child: child,
    );
  }

  static Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  /// Glass container decoration (no blur — wrap with BackdropFilter for the
  /// frosted effect). Includes a bright top light-source highlight + violet
  /// shadow for depth that makes the glass "pop out".
  static BoxDecoration glassDecoration({
    double radius = 18,
    Color? color,
    Border? border,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          (color ?? glassHeaderBottom).withValues(
            alpha: ((color ?? glassHeaderBottom).a + 0.10).clamp(0.0, 1.0),
          ),
          color ?? glassHeaderBottom,
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: border ?? Border.all(color: subtleBorder, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: glassHeaderShadow,
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  /// Wrap a widget with frosted glass effect (ClipRRect + BackdropFilter).
  /// Blur is paired with a saturation boost so colours behind the glass stay
  /// lively (the classic Apple/visionOS frosted look).
  static Widget frosted({
    required Widget child,
    double sigmaX = glassBlur,
    double sigmaY = glassBlur,
    double radius = 18,
    Color? color,
    Border? border,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
          inner: const ColorFilter.matrix(saturateMatrix),
        ),
        child: Container(
          decoration: glassDecoration(radius: radius, color: color, border: border),
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  /// Saturation-boost colour matrix (~1.3x) used with backdrop blur so the
  /// vibrant canvas stays punchy through the frosted glass. Public so widgets
  /// that build their own BackdropFilter can reuse it for a consistent look.
  static const List<double> saturateMatrix = <double>[
    1.2876, -0.2176, -0.0700, 0, 0,
    -0.1124, 1.1824, -0.0700, 0, 0,
    -0.1124, -0.2176, 1.3300, 0, 0,
    0, 0, 0, 1, 0,
  ];

  /// Returns a floating pill-style AppBar with horizontal margin and rounded corners.
  /// Uses a custom Row layout to avoid clipping issues with a nested AppBar.
  static PreferredSizeWidget floatingPillAppBar({
    required BuildContext context,
    required Widget child,
  }) {
    final topPad = MediaQuery.paddingOf(context).top;
    final totalHeight = topPad + kToolbarHeight + 10; // 10px top gap
    return PreferredSize(
      preferredSize: Size.fromHeight(totalHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, topPad + 10, 10, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.compose(
              outer: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
              inner: const ColorFilter.matrix(saturateMatrix),
            ),
            child: Container(
              height: kToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [glassHeaderTop, glassHeaderBottom],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: subtleBorder),
                boxShadow: const [
                  BoxShadow(color: glassHeaderShadow, blurRadius: 18, offset: Offset(0, 8)),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Returns a floating pill-style AppBar with frosted glass background
  static PreferredSizeWidget glassAppBar({
    required BuildContext context,
    Widget? title,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
    PreferredSizeWidget? bottom,
  }) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomHeight = bottom?.preferredSize.height ?? 0.0;
    // +4 accounts for the top padding around [bottom]; the extra tolerance
    // absorbs fractional growth when the bottom (e.g. a TabBar) renders
    // taller than its preferredSize under larger text scaling.
    final totalHeight = topPad +
        kToolbarHeight +
        10 +
        (bottom != null ? 12 + bottomHeight : 0);

    Widget? leadingWidget;
    if (leading != null) {
      leadingWidget = leading;
    } else if (automaticallyImplyLeading && Navigator.of(context).canPop()) {
      leadingWidget = ShadIconButton.ghost(
        padding: EdgeInsets.zero,
        icon: Icon(LucideIcons.arrowLeft, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      );
    }

    final hasLeading = leadingWidget != null;
    final hasActions = actions != null && actions.isNotEmpty;

    return PreferredSize(
      preferredSize: Size.fromHeight(totalHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, topPad + 10, 10, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
                  inner: const ColorFilter.matrix(saturateMatrix),
                ),
                child: Container(
                  height: kToolbarHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [glassHeaderTop, glassHeaderBottom],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: subtleBorder),
                    boxShadow: const [
                      BoxShadow(color: glassHeaderShadow, blurRadius: 18, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (hasLeading)
                        leadingWidget
                      else if (hasActions)
                        const SizedBox(width: 40),
                      
                      const SizedBox(width: 4),
                      
                      Expanded(
                        child: Center(
                          child: title != null
                              ? DefaultTextStyle(
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: AppTheme.charcoalInk,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  child: title,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      if (hasActions)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions,
                        )
                      else if (hasLeading)
                        const SizedBox(width: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: bottom,
            ),
        ],
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

  // ─────────────────────────────────────────────────────────────────────────
  // Dropdown / select / popover styling — shared so ShadSelect, ShadPopover and
  // the popup menus all look identical. Tuned per UI/UX Pro Max:
  //   • Touch targets ≥ 44px tall (option padding h:16 v:14 ≈ 48px row)
  //   • ≥ 8px spacing around the options list
  //   • Frosted-glass surface that matches the app's "pop" glassmorphism
  // ─────────────────────────────────────────────────────────────────────────

  /// Comfortable per-option padding giving a ~48px tall tap target.
  static const EdgeInsets dropdownOptionPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 14);

  /// Padding around the whole options list inside the popover.
  static const EdgeInsets dropdownListPadding = EdgeInsets.all(8);

  static const double _dropdownRadius = 18;

  /// Animations shared by every dropdown surface.
  static List<Effect<dynamic>> get _dropdownEffects => [
        FadeEffect(duration: const Duration(milliseconds: 180)),
        ScaleEffect(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
        MoveEffect(
          begin: const Offset(0, 6),
          end: Offset.zero,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      ];

  /// The frosted-glass decoration used by dropdown popovers. More opaque than
  /// the card glass so option text stays readable, but still translucent with a
  /// bright light-source border and violet shadow so it pops.
  static ShadDecoration get _dropdownDecoration => ShadDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        border: ShadBorder.all(
          color: glassBorder,
          width: 1.0,
          radius: const BorderRadius.all(Radius.circular(_dropdownRadius)),
        ),
        shadows: const [
          BoxShadow(
            color: glassShadow,
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );

  static ShadThemeData get lightTheme {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadStoneColorScheme.light(
        primary: accent,
        primaryForeground: Colors.white,
        destructive: destructive,
        destructiveForeground: Colors.white,
      ),
      // Bigger, easier-to-tap dropdown options with the brand accent on hover/
      // selection. Applies to every ShadSelect option app-wide.
      optionTheme: ShadOptionTheme(
        padding: dropdownOptionPadding,
        hoveredBackgroundColor: accent.withValues(alpha: 0.12),
        radius: BorderRadius.circular(12),
      ),
      popoverTheme: ShadPopoverTheme(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
          inner: const ColorFilter.matrix(saturateMatrix),
        ),
        effects: _dropdownEffects,
        decoration: _dropdownDecoration,
      ),
      selectTheme: ShadSelectTheme(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
          inner: const ColorFilter.matrix(saturateMatrix),
        ),
        effects: _dropdownEffects,
        decoration: _dropdownDecoration,
        optionsPadding: dropdownListPadding,
        // Keep dropdowns readable and reachable on small screens — never wider
        // than the viewport, and capped height so long lists scroll.
        minWidth: 180,
        maxHeight: 320,
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
      // Same generous tap targets in dark mode.
      optionTheme: ShadOptionTheme(
        padding: dropdownOptionPadding,
        hoveredBackgroundColor: accent.withValues(alpha: 0.22),
        radius: BorderRadius.circular(12),
      ),
      popoverTheme: ShadPopoverTheme(
        filter: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
        effects: _dropdownEffects,
        decoration: ShadDecoration(
          color: const Color(0xF01C1917),
          border: ShadBorder.all(
            color: const Color(0x4DAAAAAA),
            width: 1.0,
            radius: const BorderRadius.all(Radius.circular(_dropdownRadius)),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
      ),
      selectTheme: ShadSelectTheme(
        filter: ImageFilter.blur(sigmaX: glassBlurHeavy, sigmaY: glassBlurHeavy),
        effects: _dropdownEffects,
        optionsPadding: dropdownListPadding,
        minWidth: 180,
        maxHeight: 320,
        decoration: ShadDecoration(
          color: const Color(0xF01C1917),
          border: ShadBorder.all(
            color: const Color(0x4DAAAAAA),
            width: 1.0,
            radius: const BorderRadius.all(Radius.circular(_dropdownRadius)),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Material [PopupMenuThemeData] matching the app's glass dropdown style.
  /// Shared by every `PopupMenuButton` so they look like the ShadSelect
  /// dropdowns: frosted surface, bright border, deep-violet text, and roomy
  /// items for easy tapping.
  static PopupMenuThemeData popupMenuTheme({required bool isDark}) {
    return PopupMenuThemeData(
      position: PopupMenuPosition.under,
      color: isDark
          ? const Color(0xF01C1917)
          : Colors.white.withValues(alpha: 0.9),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: isDark ? const Color(0x66000000) : glassShadow,
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      // Bigger label text + comfortable item height for easy tapping.
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : charcoalInk,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_dropdownRadius),
        side: BorderSide(
          color: isDark ? const Color(0x4DAAAAAA) : glassBorder,
          width: 1.0,
        ),
      ),
    );
  }

  /// Minimum height for a comfortable, easy-to-tap menu/list row (≥44px is the
  /// platform-recommended touch target; we use 48 for extra comfort).
  static const double minTapTarget = 48.0;

  /// Solid-surface dialog — clean white card with a purple accent top bar,
  /// deep shadow, and fully opaque background so all content is crisp and
  /// readable regardless of what is behind the dialog.
  ///
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
      // Darker scrim so the white card pops cleanly off the screen.
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => AnimatedPadding(
        padding: MediaQuery.of(ctx).viewInsets +
            const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: MediaQuery.removeViewInsets(
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          context: ctx,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: pureSurface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x28000000),
                        blurRadius: 40,
                        offset: Offset(0, 16),
                      ),
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Accent top bar ──────────────────────────────
                        Container(
                          height: 4,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accent, accentBright],
                            ),
                          ),
                        ),
                        // ── Content ─────────────────────────────────────
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
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
                                              fontWeight: FontWeight.w700,
                                              color: charcoalInk,
                                              height: 1.3,
                                            ),
                                            child: title,
                                          ),
                                        if (description != null) ...[
                                          const SizedBox(height: 8),
                                          DefaultTextStyle(
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: mutedSteel,
                                              height: 1.5,
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
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Wrap(
                                              alignment: WrapAlignment.end,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: actions,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Custom page transition: fade + subtle slide up
  static Route<T> fadeSlideRoute<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
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
