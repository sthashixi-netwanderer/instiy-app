import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/scanner_overlay.dart';

class ScannerScreen extends StatefulWidget {
  final void Function(String code) onDetect;

  const ScannerScreen({super.key, required this.onDetect});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasDetected = false;

  Rect? _detectedRect;
  Timer? _clearDetectedRectTimer;
  Size? _lastPreviewSize;
  Size? _lastWidgetSize;

  @override
  void dispose() {
    _controller.dispose();
    _clearDetectedRectTimer?.cancel();
    super.dispose();
  }

  Rect _mapRectToScreen(Rect rect, Size previewSize, Size widgetSize) {
    final scaleX = widgetSize.width / previewSize.width;
    final scaleY = widgetSize.height / previewSize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final offsetX = (widgetSize.width - previewSize.width * scale) / 2;
    final offsetY = (widgetSize.height - previewSize.height * scale) / 2;

    final mappedRect = Rect.fromLTRB(
      rect.left * scale + offsetX,
      rect.top * scale + offsetY,
      rect.right * scale + offsetX,
      rect.bottom * scale + offsetY,
    );

    return mappedRect.inflate(16);
  }

  Rect? _getBoundingBox(List<Offset>? points) {
    if (points == null || points.isEmpty) return null;
    double left = points[0].dx;
    double top = points[0].dy;
    double right = points[0].dx;
    double bottom = points[0].dy;

    for (final point in points) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_hasDetected) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    _lastPreviewSize = capture.size;
    final boundingBox = _getBoundingBox(barcode.corners);

    if (boundingBox != null && _lastPreviewSize != null && _lastWidgetSize != null) {
      final screenRect = _mapRectToScreen(boundingBox, _lastPreviewSize!, _lastWidgetSize!);
      setState(() {
        _detectedRect = screenRect;
      });

      _clearDetectedRectTimer?.cancel();
      _clearDetectedRectTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _detectedRect = null;
          });
        }
      });
    }

    _hasDetected = true;

    // Brief delay to show target frame snapping
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    _controller.stop();
    widget.onDetect(barcode.rawValue!);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Delivery Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _lastWidgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
              AnimatedScannerOverlay(
                cutOutSize: 250,
                borderRadius: 16,
                borderWidth: 3,
                detectedRect: _detectedRect,
              ),
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Text(
                  'Point camera at the QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
