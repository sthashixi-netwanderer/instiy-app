import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class WatermarkService {
  /// Adds a watermark to an image file with store name and "Posted on Instiy".
  /// Returns a new temporary file with the watermarked image.
  static Future<File> addWatermark({
    required File imageFile,
    required String storeName,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return imageFile;

    final width = image.width;
    final height = image.height;

    // Create semi-transparent overlay for the watermark area
    final watermarkHeight = (height * 0.12).round().clamp(60, 200);
    final overlay = img.Image(width: width, height: watermarkHeight);

    // Draw dark gradient overlay (semi-transparent black from top to bottom)
    for (int y = 0; y < watermarkHeight; y++) {
      final opacity = (140 * (y / watermarkHeight)).round().clamp(0, 140);
      for (int x = 0; x < width; x++) {
        overlay.setPixelRgba(x, y, 0, 0, 0, opacity);
      }
    }

    // Composite the overlay onto the bottom of the image
    img.compositeImage(image, overlay, dstX: 0, dstY: height - watermarkHeight);

    // Use arial24 for store name (larger) and arial14 for subtext (smaller)
    final font24 = img.arial24;
    final font14 = img.arial14;

    final padding = (width * 0.04).round();
    final storeY = height - watermarkHeight + padding;
    final subY = storeY + 30;

    // Draw store name (white)
    img.drawString(
      image,
      storeName.length > 30 ? '${storeName.substring(0, 27)}...' : storeName,
      x: padding,
      y: storeY,
      color: img.ColorUint8.rgb(255, 255, 255),
      font: font24,
    );

    // Draw "Posted on Instiy" (lighter white)
    img.drawString(
      image,
      'Posted on Instiy',
      x: padding,
      y: subY,
      color: img.ColorUint8.rgb(200, 200, 200),
      font: font14,
    );

    // Encode back to JPEG
    final watermarkedBytes = img.encodeJpg(image, quality: 90);

    // Write to temp file
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/watermarked_${Random().nextInt(999999)}.jpg');
    await tempFile.writeAsBytes(watermarkedBytes);

    return tempFile;
  }
}
