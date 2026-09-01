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
    String name = (xFile.name as String?) ?? '';
    if (name.isEmpty && path != null) {
      name = path.split('/').last.split('\\').last;
    }
    if (name.isEmpty) {
      name = 'picked_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    return PickedMedia(bytes: bytes, name: name, path: path);
  }

  static const _validExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'mp4',
    'mov',
    'webm',
    'pdf',
    'm4a',
  };

  /// Sniffs byte magic headers to determine actual file format.
  static String? detectExtension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'pdf';
    }
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'mp4';
    }
    return null;
  }

  /// File extension derived from byte signature or [name]/[path] (e.g. 'jpg', 'png', 'mp4').
  String get extension {
    final magic = detectExtension(bytes);
    if (magic != null) return magic;

    final fromName = _extractExt(name);
    if (fromName != null && _validExtensions.contains(fromName)) {
      return fromName == 'jpeg' ? 'jpg' : fromName;
    }

    final fromPath = _extractExt(path);
    if (fromPath != null && _validExtensions.contains(fromPath)) {
      return fromPath == 'jpeg' ? 'jpg' : fromPath;
    }

    return 'jpg';
  }

  static String? _extractExt(String? input) {
    if (input == null || input.isEmpty) return null;
    final clean = input.split('?').first.split('#').first;
    final parts = clean.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase().trim();
    }
    return null;
  }

  bool get isVideo {
    const videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv'};
    return videoExts.contains(extension);
  }

  /// Dispose bytes when no longer needed (optional, helps GC on mobile).
  void dispose() => bytes.buffer;
}
