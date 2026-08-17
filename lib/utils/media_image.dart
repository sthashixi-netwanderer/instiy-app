import 'package:flutter/material.dart';
import '../models/picked_media.dart';

// Conditional import: mobile uses FileImage, web uses MemoryImage.
import 'media_image_native.dart'
    if (dart.library.js_interop) 'media_image_web.dart';

export 'media_image_native.dart'
    if (dart.library.js_interop) 'media_image_web.dart';

/// Returns an [ImageProvider] that works on both mobile and web.
ImageProvider mediaImageProvider(PickedMedia media) {
  return createImageProvider(media);
}

/// Convenience widget that displays a [PickedMedia] as a circle avatar.
class PickedMediaAvatar extends StatelessWidget {
  final PickedMedia media;
  final double radius;
  final Widget? fallback;

  const PickedMediaAvatar({
    super.key,
    required this.media,
    this.radius = 30,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: mediaImageProvider(media),
      child: fallback,
    );
  }
}

/// Returns a [BoxDecoration] for displaying a [PickedMedia] as a background image.
BoxDecoration mediaDecoration(PickedMedia media) {
  return BoxDecoration(
    image: DecorationImage(
      image: mediaImageProvider(media),
      fit: BoxFit.cover,
    ),
  );
}
