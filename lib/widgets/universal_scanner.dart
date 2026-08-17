import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';
import 'scanner_overlay.dart';

class UniversalScanner extends StatefulWidget {
  final void Function(String code) onDetect;
  final String title;
  final String subtitle;
  final double cutOutSize;

  const UniversalScanner({
    super.key,
    required this.onDetect,
    this.title = 'Scan QR Code',
    this.subtitle = 'Align the QR code within the frame',
    this.cutOutSize = 250,
  });

  @override
  State<UniversalScanner> createState() => _UniversalScannerState();
}

enum _CameraState { checking, granted, denied, permanentlyDenied }

class _UniversalScannerState extends State<UniversalScanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MobileScannerController _scannerController;
  late final AnimationController _scanLineController;
  bool _hasDetected = false;
  _CameraState _cameraState = _CameraState.checking;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _inactivityTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });

    // Always locked to back camera, autoStart disabled — we start manually
    // after the permission check so the camera surface is ready.
    //
    // Performance tuning:
    //  • DetectionSpeed.normal — `noDuplicates` keeps an ever-growing barcode
    //    history to dedupe against, which degrades over time. We handle dedupe
    //    ourselves with `_hasDetected`, so `normal` is both faster and lighter.
    //  • cameraResolution 720p — the default uses the sensor's max resolution,
    //    which is very expensive to run ML detection on every frame and is the
    //    main cause of lag / dropped frames on mid/low-end devices. 720p is
    //    more than enough to read a QR code and keeps the pipeline smooth.
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 250,
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
      cameraResolution: const Size(1280, 720),
      autoStart: false,
    );

    _scanLineController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);

    // Request permission then start the camera after the first frame so the
    // widget tree (and the camera surface texture) is fully attached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    if (!mounted) return;

    // Check current status first to avoid an unnecessary dialog pop-up.
    var status = await Permission.camera.status;

    if (status.isDenied) {
      // Not yet asked — request it now.
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (status.isGranted || status.isLimited) {
      setState(() => _cameraState = _CameraState.granted);
      // Small delay so the MobileScanner widget is fully laid out before
      // the native camera tries to bind to its texture.
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) _scannerController.start(); // ignore: unawaited_futures
    } else if (status.isPermanentlyDenied) {
      setState(() => _cameraState = _CameraState.permanentlyDenied);
    } else {
      setState(() => _cameraState = _CameraState.denied);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraState != _CameraState.granted) return;
    if (!_scannerController.value.isInitialized) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _scannerController.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _scannerController.stop();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _scannerController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected || !mounted) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue;
    if (value == null || value.isEmpty) return;

    _inactivityTimer?.cancel();

    // Lock immediately so duplicate frames in the same burst don't double-fire.
    _hasDetected = true;
    widget.onDetect(value);

    // Re-arm only if this widget is still mounted (i.e. the caller didn't
    // navigate away). Prevents a stray timer firing on a disposed state.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _hasDetected = false;
    });
  }

  // ── Permission-denied UI ──────────────────────────────────────────────────
  Widget _buildPermissionDenied({required bool permanent}) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.cameraOff, color: Colors.white70, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Camera Access Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                permanent
                    ? 'Camera permission was permanently denied. Please enable it in your device Settings to scan QR codes.'
                    : 'Camera permission is needed to scan QR codes. Please allow access when prompted.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              ShadButton(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                onPressed: permanent ? openAppSettings : _initCamera,
                leading: Icon(
                  permanent ? LucideIcons.settings : LucideIcons.refreshCw,
                  size: 16,
                ),
                child: Text(permanent ? 'Open Settings' : 'Grant Permission'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Loading UI ────────────────────────────────────────────────────────────
  Widget _buildChecking() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            SizedBox(height: 16),
            Text(
              'Starting camera…',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Web: QR scanning is not available — show a message.
    if (kIsWeb) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.qrCode, color: Colors.white70, size: 48),
                ),
                const SizedBox(height: 24),
                const Text(
                  'QR Scanning Not Available on Web',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Please use the mobile app to scan QR codes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 28),
                ShadButton(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show appropriate UI based on permission state
    if (_cameraState == _CameraState.checking) return _buildChecking();
    if (_cameraState == _CameraState.denied) {
      return _buildPermissionDenied(permanent: false);
    }
    if (_cameraState == _CameraState.permanentlyDenied) {
      return _buildPermissionDenied(permanent: true);
    }

    // Permission granted — show the live scanner
    return Stack(
      children: [
        // Isolate the camera preview in its own layer so overlay/animation
        // repaints never invalidate the camera texture.
        RepaintBoundary(
          child: MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          // Cap the texture to the screen size — avoids the engine uploading a
          // huge camera texture every frame.
          fit: BoxFit.cover,
          errorBuilder: (context, error) {
            return Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.cameraOff, color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Camera error: ${error.errorCode.name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ShadButton.outline(
                      foregroundColor: Colors.white,
                      onPressed: () {
                        _scannerController.stop();
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted) _scannerController.start();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          },
          ),
        ),
        ScannerOverlay(
          cutOutSize: widget.cutOutSize,
          scanLineAnimation: _scanLineController,
        ),
        // Header
        Positioned(
          top: context.rh(50),
          left: 16,
          right: 16,
          child: Column(
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: context.rsp(20),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
              ),
              SizedBox(height: context.rh(8)),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: context.rsp(14),
                  shadows: const [
                    Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Bottom controls — torch only, no camera switch
        Positioned(
          bottom: context.rh(40),
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, _) {
                final isOn = state.torchState == TorchState.on;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: ClipOval(
                    child: Container(
                      color: isOn ? AppTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
                      child: IconButton(
                        icon: Icon(
                          isOn ? LucideIcons.flashlight : LucideIcons.flashlightOff,
                          color: isOn ? AppTheme.accent : Colors.white,
                          size: 20,
                        ),
                        onPressed: _scannerController.toggleTorch,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
