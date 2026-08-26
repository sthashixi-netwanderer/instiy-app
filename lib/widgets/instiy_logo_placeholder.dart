import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_theme.dart';

/// The Instiy logo shown as a placeholder while product/clip content loads.
///
/// Defaults to the light theme treatment (lilac mist background, muted violet
/// logo). Pass [animate] for a gentle breathing pulse in loading states, or
/// override [backgroundColor]/[logoColor] for dark surfaces such as the clip
/// feed.
class InstiyLogoPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;

  /// Gentle opacity pulse while content is loading.
  final bool animate;

  /// Explicit logo edge size. Defaults to ~45% of the smallest dimension
  /// (48px when unbounded), capped by whatever constraints apply.
  final double? logoSize;
  final Color? backgroundColor;
  final Color? logoColor;
  final BorderRadius borderRadius;

  const InstiyLogoPlaceholder({
    super.key,
    this.width,
    this.height,
    this.animate = false,
    this.logoSize,
    this.backgroundColor,
    this.logoColor,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final candidates = <double?>[
          logoSize,
          ?width,
          ?height,
          if (constraints.hasBoundedWidth) constraints.maxWidth,
          if (constraints.hasBoundedHeight) constraints.maxHeight,
        ]
            .whereType<double>()
            .where((v) => v > 0 && v.isFinite)
            .toList();
        final base =
            candidates.isEmpty ? 48 : candidates.reduce((a, b) => a < b ? a : b);
        final size = logoSize ?? base * 0.45;

        final Widget logo = SvgPicture.asset(
          'assets/logo.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            logoColor ?? AppTheme.mutedSteel,
            BlendMode.srcIn,
          ),
        );

        return Container(
          width: width,
          height: height,
          clipBehavior:
              borderRadius == BorderRadius.zero ? Clip.none : Clip.antiAlias,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.warmMist,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: animate ? _PulsingOpacity(child: logo) : logo,
          ),
        );
      },
    );
  }
}

/// Breathing opacity loop used by [InstiyLogoPlaceholder.animate].
class _PulsingOpacity extends StatefulWidget {
  final Widget child;

  const _PulsingOpacity({required this.child});

  @override
  State<_PulsingOpacity> createState() => _PulsingOpacityState();
}

class _PulsingOpacityState extends State<_PulsingOpacity>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}
