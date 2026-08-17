import 'package:flutter/material.dart';
import '../models/picked_media.dart';

/// Web: always use MemoryImage from bytes.
ImageProvider createImageProvider(PickedMedia media) {
  return MemoryImage(media.bytes);
}
