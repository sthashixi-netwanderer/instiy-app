import 'dart:io';
import 'package:flutter/material.dart';
import '../models/picked_media.dart';

/// Native: use FileImage when path is available, MemoryImage otherwise.
ImageProvider createImageProvider(PickedMedia media) {
  if (media.path != null) {
    return FileImage(File(media.path!));
  }
  return MemoryImage(media.bytes);
}
