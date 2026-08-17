import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class ScannerOverlay extends StatelessWidget {
  final double cutOutSize;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Color overlayColor;
  final Animation<double> scanLineAnimation;

  const ScannerOverlay({
    super.key,
    required this.cutOutSize,
    required this.scanLineAnimation,
    this.borderColor = AppTheme.accent,
    this.borderWidth = 4.0,
    this.borderRadius = 16.0,
    this.overlayColor = const Color(0x99000000),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final left = (w - cutOutSize) / 2;
        final top = (h - cutOutSize) / 2;

        // The static parts (dim mask + border) never change, so they live in
        // their own RepaintBoundary and are painted ONCE. Only the thin scan
        // line repaints each frame, isolated in its own RepaintBoundary so it
        // never invalidates the camera texture or the mask layer. This removes
        // the per-frame Stack rebuild that was competing with camera frames.
        return Stack(
          children: [
            RepaintBoundary(
              child: Stack(
                children: [
                  // Dark overlay — 4 rectangles around the cutout
                  Positioned(top: 0, left: 0, right: 0, height: top.clamp(0.0, h),
                      child: Container(color: overlayColor)),
                  Positioned(bottom: 0, left: 0, right: 0,
                      height: (h - top - cutOutSize).clamp(0.0, h),
                      child: Container(color: overlayColor)),
                  Positioned(top: top, left: 0, width: left.clamp(0.0, w),
                      height: cutOutSize, child: Container(color: overlayColor)),
                  Positioned(top: top, right: 0,
                      width: (w - left - cutOutSize).clamp(0.0, w),
                      height: cutOutSize, child: Container(color: overlayColor)),
                  // Cutout border
                  Positioned(
                    left: left, top: top,
                    width: cutOutSize, height: cutOutSize,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor, width: borderWidth),
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Animated scan line — isolated repaint, only this 2px line redraws.
            Positioned(
              left: left + 12,
              top: top + 8,
              width: cutOutSize - 24,
              height: cutOutSize - 16,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: scanLineAnimation,
                  builder: (context, child) {
                    return Align(
                      alignment: Alignment(0, -1 + 2 * scanLineAnimation.value),
                      child: child,
                    );
                  },
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
