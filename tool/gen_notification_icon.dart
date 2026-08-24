import 'dart:io';
import 'package:image/image.dart';

/// Generates the Android notification small icon (white alpha silhouette of
/// the project logo) into all density buckets, plus verifies output.
/// Status-bar icons are rendered as an alpha mask by Android 5+, so artwork
/// must be white-on-transparent — a colored launcher icon shows as a blob.
void main() {
  final src = decodePng(File('assets/logo_highres.png').readAsBytesSync())!;
  final cropped = trim(src, mode: TrimMode.transparent);
  print('source 1024 -> cropped ${cropped.width}x${cropped.height}');

  final resRoot = 'android/app/src/main/res';
  const sizes = {
    'drawable-mdpi': 24,
    'drawable-hdpi': 36,
    'drawable-xhdpi': 48,
    'drawable-xxhdpi': 72,
    'drawable-xxxhdpi': 96,
  };

  for (final e in sizes.entries) {
    final size = e.value;
    final scaled = copyResize(
      cropped,
      width: size,
      height: size,
      interpolation: Interpolation.average,
    );
    final out = Image(width: size, height: size, numChannels: 4);
    for (final p in scaled) {
      // White silhouette: keep the logo's exact alpha, flat white fill.
      out.setPixelRgba(p.x, p.y, 255, 255, 255, p.a);
    }
    final path = '$resRoot/${e.key}/ic_notification.png';
    File(path).writeAsBytesSync(encodePng(out));
    print('wrote $path (${File(path).lengthSync()} bytes)');
  }
}
