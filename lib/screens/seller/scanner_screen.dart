import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/universal_scanner.dart';

class ScannerScreen extends ConsumerWidget {
  /// Called with the raw scanned value. Omit it together with [autoClose]
  /// and read the value from the route result instead
  /// (`final code = await Navigator.push<String>(...)`).
  final void Function(String code)? onDetect;

  /// Pops the scanner by itself right after a code is read, returning the
  /// value as the route result.
  final bool autoClose;

  const ScannerScreen({
    super.key,
    this.onDetect,
    this.autoClose = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Delivery Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: UniversalScanner(
        title: 'Scan Delivery Code',
        subtitle: 'Point camera at the QR code to verify delivery',
        autoClose: autoClose,
        onDetect: onDetect,
      ),
    );
  }
}
