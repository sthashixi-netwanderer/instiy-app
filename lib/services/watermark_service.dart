import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class WatermarkService {
  /// Adds an Adobe Stock-style translucent diagonal repeating watermark
  /// across the center of the image. The watermark uses the store name
  /// and "Posted on Instiy" text.
  static Future<File> addWatermark({
    required File imageFile,
    required String storeName,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return imageFile;

    final width = image.width;
    final height = image.height;

    final displayName = storeName.length > 30
        ? '${storeName.substring(0, 27)}...'
        : storeName;

    final font24 = img.arial24;
    final font14 = img.arial14;

    // Fixed tile size — large enough for two lines of text with padding
    final tileWidth = 300;
    final tileHeight = 80;

    // Create transparent tile
    final tile = img.Image(width: tileWidth, height: tileHeight, numChannels: 4);

    // Draw store name (white)
    img.drawString(tile, displayName, x: 12, y: 8,
        color: img.ColorUint8.rgb(255, 255, 255), font: font24);

    // Draw "Posted on Instiy" (white)
    img.drawString(tile, 'Posted on Instiy', x: 12, y: 42,
        color: img.ColorUint8.rgb(255, 255, 255), font: font14);

    // Rotate the tile -45 degrees (diagonal)
    final rotatedTile = img.copyRotate(tile, angle: -45);

    // Apply global alpha to make the entire rotated tile translucent (~20%)
    final alpha = 50;
    final translucentTile = img.Image(
      width: rotatedTile.width,
      height: rotatedTile.height,
      numChannels: 4,
    );
    for (int y = 0; y < rotatedTile.height; y++) {
      for (int x = 0; x < rotatedTile.width; x++) {
        final pixel = rotatedTile.getPixel(x, y);
        final blendedA = (pixel.a.toInt() * alpha ~/ 255).clamp(0, 255);
        translucentTile.setPixelRgba(
          x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), blendedA,
        );
      }
    }

    // Tile the watermark across the center 60% of the image
    final tileW = translucentTile.width;
    final tileH = translucentTile.height;
    final startY = (height * 0.2).toInt();
    final endY = (height * 0.8).toInt();

    for (int y = startY; y < endY; y += tileH) {
      for (int x = -tileW; x < width + tileW; x += tileW) {
        img.compositeImage(image, translucentTile, dstX: x, dstY: y);
      }
    }

    // Encode back to JPEG
    final watermarkedBytes = img.encodeJpg(image, quality: 90);

    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/watermarked_${Random().nextInt(999999)}.jpg');
    await tempFile.writeAsBytes(watermarkedBytes);

    return tempFile;
  }
}
