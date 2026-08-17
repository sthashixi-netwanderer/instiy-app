import 'package:flutter/foundation.dart';

/// A platform-agnostic container for picked media (images/videos).
///
/// On mobile, [path] points to the temporary file on disk. On web, [path]
/// is null and only [bytes] is available. All upload code should use [bytes];
/// display code should use [mediaImageProvider] from `utils/media_image.dart`.
class PickedMedia {
  final Uint8List bytes;
  final String name;
  final String? path;

  const PickedMedia({
    required this.bytes,
    required this.name,
    this.path,
  });

  bool get hasFile => path != null && !kIsWeb;

  /// Build from an [XFile] returned by `image_picker` on mobile.
  static Future<PickedMedia> fromXFile(dynamic xFile) async {
    final bytes = await xFile.readAsBytes();
    final path = kIsWeb ? null : xFile.path;
    final name = xFile.name ?? 'picked_${DateTime.now().millisecondsSinceEpoch}';
    return PickedMedia(bytes: bytes, name: name, path: path);
  }

  /// File extension derived from [name] (e.g. 'jpg', 'mp4').
  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
  }

  bool get isVideo {
    const videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv'};
    return videoExts.contains(extension);
  }

  /// Dispose bytes when no longer needed (optional, helps GC on mobile).
  void dispose() => bytes.buffer;
}
