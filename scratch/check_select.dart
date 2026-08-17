import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  final theme = ShadThemeData(
    brightness: Brightness.light,
    popoverTheme: ShadPopoverTheme(
      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
      effects: [
        FadeEffect(duration: const Duration(milliseconds: 150)),
        ScaleEffect(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        ),
      ],
      decoration: ShadDecoration(
        color: const Color(0xEBF5F2EF),
        border: ShadBorder.all(
          color: const Color(0x59C8C0B8),
          width: 0.5,
          radius: const BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
  );
  print(theme);
}
