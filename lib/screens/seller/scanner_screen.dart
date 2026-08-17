import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/universal_scanner.dart';

class ScannerScreen extends ConsumerWidget {
  final void Function(String code) onDetect;

  const ScannerScreen({super.key, required this.onDetect});

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
        onDetect: (code) {
          onDetect(code);
        },
      ),
    );
  }
}
