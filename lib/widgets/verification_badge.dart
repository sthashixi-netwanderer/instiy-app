import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class VerificationBadge extends StatelessWidget {
  final double size;

  const VerificationBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/badge-check-svgrepo-com.svg',
      width: size,
      height: size,
    );
  }
}
