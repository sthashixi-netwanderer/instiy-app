import 'package:video_player/video_player.dart';

/// Web: always stream from network — no filesystem cache available.
VideoPlayerController createVideoControllerNative(String url, {dynamic cachedFile}) {
  return VideoPlayerController.networkUrl(Uri.parse(url));
}
