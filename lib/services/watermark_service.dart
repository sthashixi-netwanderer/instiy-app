import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/picked_media.dart';

/// Burns a subtle "Posted on Instiy" + store name watermark into listing
/// images before upload, so shared/saved copies stay attributed to the app
/// and the seller wherever they travel.
class WatermarkService {
  /// Watermark opacity (alpha 0–255). Kept low so the pattern labels the
  /// content without hiding it.
  static const _alpha = 60;

  /// Adds a translucent diagonal repeating watermark across the center of
  /// the image: the store name and "Posted on Instiy". Returns a new
  /// [PickedMedia] with the watermarked JPEG bytes; on any failure the
  /// original media is returned untouched.
  static Future<PickedMedia> addWatermark({
    required PickedMedia media,
    String? storeName,
  }) async {
    final label = (storeName ?? '').trim();
    if (label.isEmpty) return media;

    try {
      final displayName = label.length > 30 ? '${label.substring(0, 27)}...' : label;
      final source = media.bytes;
      final watermarked = await Isolate.run(
        () => _watermarkBytes(source, displayName),
      );
      // Output is re-encoded as JPEG — keep the name in sync so the upload
      // gets the right content type.
      final dot = media.name.lastIndexOf('.');
      final baseName = dot > 0 ? media.name.substring(0, dot) : media.name;
      return PickedMedia(
        bytes: watermarked,
        name: '$baseName.jpg',
        path: null,
      );
    } catch (_) {
      return media;
    }
  }

  static Uint8List _watermarkBytes(Uint8List bytes, String displayName) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Tile with two lines of text: store name + app attribution. A dark
    // shadow copy under the white text keeps the watermark readable on
    // bright photos while staying subtle.
    const tileWidth = 320;
    const tileHeight = 80;
    final tile = img.Image(width: tileWidth, height: tileHeight, numChannels: 4);

    img.drawString(tile, displayName, x: 13, y: 9,
        font: img.arial24, color: img.ColorUint8.rgb(35, 35, 35));
    img.drawString(tile, displayName, x: 12, y: 8,
        font: img.arial24, color: img.ColorUint8.rgb(255, 255, 255));

    img.drawString(tile, 'Posted on Instiy', x: 13, y: 43,
        font: img.arial14, color: img.ColorUint8.rgb(35, 35, 35));
    img.drawString(tile, 'Posted on Instiy', x: 12, y: 42,
        font: img.arial14, color: img.ColorUint8.rgb(255, 255, 255));

    final rotatedTile = img.copyRotate(tile, angle: -45);

    // Scale the whole rotated tile's alpha down for the see-through look.
    final translucentTile = img.Image(
      width: rotatedTile.width,
      height: rotatedTile.height,
      numChannels: 4,
    );
    for (int y = 0; y < rotatedTile.height; y++) {
      for (int x = 0; x < rotatedTile.width; x++) {
        final pixel = rotatedTile.getPixel(x, y);
        final blendedA = (pixel.a.toInt() * _alpha ~/ 255).clamp(0, 255);
        translucentTile.setPixelRgba(
          x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), blendedA,
        );
      }
    }

    // Tile across the middle band of the image, leaving top and bottom
    // clear so faces/products stay readable.
    final tileW = translucentTile.width;
    final tileH = translucentTile.height;
    final startY = (image.height * 0.2).toInt();
    final endY = (image.height * 0.8).toInt();

    for (int y = startY; y < endY; y += tileH) {
      for (int x = -tileW; x < image.width + tileW; x += tileW) {
        img.compositeImage(image, translucentTile, dstX: x, dstY: y);
      }
    }

    return img.encodeJpg(image, quality: 90);
  }
}
