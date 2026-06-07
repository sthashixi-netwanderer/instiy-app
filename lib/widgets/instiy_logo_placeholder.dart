import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_theme.dart';

/// A greyed-out Instiy logo used as a placeholder during image lazy loading.
class InstiyLogoPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;

  const InstiyLogoPlaceholder({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppTheme.warmMist,
      child: Center(
        child: SvgPicture.asset(
          'assets/logo.svg',
          width: (width ?? 48) * 0.5,
          height: (height ?? 48) * 0.5,
          colorFilter: const ColorFilter.mode(
            AppTheme.mutedSteel,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
