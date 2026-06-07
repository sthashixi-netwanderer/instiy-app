import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class AnimatedScannerOverlay extends StatefulWidget {
  final double cutOutSize;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Color overlayColor;
  final Color lineColor;
  final Rect? detectedRect; // The currently detected QR code bounds on screen

  const AnimatedScannerOverlay({
    super.key,
    this.cutOutSize = 250.0,
    this.borderColor = AppTheme.accent,
    this.borderWidth = 4.0,
    this.borderRadius = 16.0,
    this.overlayColor = const Color(0x99000000), // semi-transparent black
    this.lineColor = AppTheme.accent,
    this.detectedRect,
  });

  @override
  State<AnimatedScannerOverlay> createState() => _AnimatedScannerOverlayState();
}

class _AnimatedScannerOverlayState extends State<AnimatedScannerOverlay>
    with TickerProviderStateMixin {
  late AnimationController _lineController;
  late AnimationController _positionController;
  late Animation<Rect?> _rectAnimation;
  Rect _currentRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _positionController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _rectAnimation = RectTween(
      begin: Rect.zero,
      end: Rect.zero,
    ).animate(_positionController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final defaultRect = _getDefaultRect(size);
    if (_currentRect == Rect.zero) {
      _currentRect = defaultRect;
      _rectAnimation = RectTween(
        begin: defaultRect,
        end: defaultRect,
      ).animate(_positionController);
    }
  }

  @override
  void didUpdateWidget(AnimatedScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detectedRect != oldWidget.detectedRect) {
      final size = MediaQuery.of(context).size;
      final fromRect = _rectAnimation.value ?? _currentRect;
      final toRect = widget.detectedRect ?? _getDefaultRect(size);

      _rectAnimation = RectTween(
        begin: fromRect,
        end: toRect,
      ).animate(CurvedAnimation(
        parent: _positionController,
        curve: Curves.easeOutCubic,
      ));

      _currentRect = toRect;
      _positionController.reset();
      _positionController.forward();
    }
  }

  @override
  void dispose() {
    _lineController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  Rect _getDefaultRect(Size screenSize) {
    return Rect.fromCenter(
      center: Offset(screenSize.width / 2, screenSize.height / 2),
      width: widget.cutOutSize,
      height: widget.cutOutSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: Listenable.merge([_positionController, _lineController]),
      builder: (context, child) {
        final currentCutout = _rectAnimation.value ?? _getDefaultRect(size);

        return Stack(
          children: [
            // 1. Dark overlay with custom cutout shape
            Positioned.fill(
              child: Container(
                decoration: ShapeDecoration(
                  shape: _DynamicScannerOverlayShape(
                    borderColor: widget.borderColor,
                    borderWidth: widget.borderWidth,
                    borderRadius: widget.borderRadius,
                    cutOutRect: currentCutout,
                    overlayColor: widget.overlayColor,
                  ),
                ),
              ),
            ),
            // 2. Animated scanning line restricted to cutout bounds
            Positioned(
              left: currentCutout.left + 8,
              top: currentCutout.top + 8 + _lineController.value * (currentCutout.height - 16),
              width: currentCutout.width - 16,
              height: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.lineColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: widget.lineColor.withValues(alpha: 0.8),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DynamicScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Rect cutOutRect;
  final Color overlayColor;

  const _DynamicScannerOverlayShape({
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.cutOutRect,
    required this.overlayColor,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)));
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final borderPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()..addRect(rect);

    final cutOutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)));

    final overlayPath = Path.combine(PathOperation.difference, backgroundPath, cutOutPath);
    canvas.drawPath(overlayPath, borderPaint);

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
      strokePaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return _DynamicScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      borderRadius: borderRadius * t,
      cutOutRect: cutOutRect,
      overlayColor: overlayColor,
    );
  }
}
