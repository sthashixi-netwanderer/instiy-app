import 'dart:io';
import 'package:video_player/video_player.dart';

/// Native: create video controller from cached file or network URL.
VideoPlayerController createVideoControllerNative(String url, {File? cachedFile}) {
  if (cachedFile != null) {
    return VideoPlayerController.file(cachedFile);
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}
