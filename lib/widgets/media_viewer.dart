import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_theme.dart';
import '../services/storage_service.dart';
import '../services/video_service.dart';
import '../utils/responsive.dart';

class MediaViewer extends StatefulWidget {
  final List<String> mediaUrls;
  final int initialIndex;

  const MediaViewer({
    super.key,
    required this.mediaUrls,
    this.initialIndex = 0,
  });

  static void open(BuildContext context, List<String> mediaUrls, {int initialIndex = 0}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => MediaViewer(
          mediaUrls: mediaUrls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController> _videoControllers = {};
  bool _isDismissing = false;
  double _dismissOpacity = 1.0;
  double _dismissScale = 1.0;
  double _dragOffsetY = 0;
  bool _isSaving = false;
  bool _isMuted = false;
  final Map<int, bool> _hasAudioMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _initVideoForIndex(_currentIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    for (final vc in _videoControllers.values) {
      vc.dispose();
    }
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  void _initVideoForIndex(int index) {
    final url = widget.mediaUrls[index];
    if (!_isVideo(url)) return;
    if (_videoControllers.containsKey(index)) return;

    final vc = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoControllers[index] = vc;
    vc.initialize().then((_) async {
      if (mounted) {
        // Check if video has audio track
        final hasAudio = await VideoService.checkVideoHasAudio(url);
        if (mounted) {
          setState(() {
            _hasAudioMap[index] = hasAudio;
          });
        }
        vc.setLooping(true);
        vc.setVolume((_isMuted || !hasAudio) ? 0.0 : 1.0);
        vc.play();
      }
    });
  }

  void _onPageChanged(int index) {
    // Pause previous video
    _videoControllers[_currentIndex]?.pause();

    setState(() => _currentIndex = index);
    _initVideoForIndex(index);

    // Auto-play new video if it's ready
    final vc = _videoControllers[index];
    if (vc != null && vc.value.isInitialized) {
      vc.play();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0 && _dragOffsetY == 0) return;

    setState(() {
      _dragOffsetY += details.delta.dy;
      if (_dragOffsetY < 0) _dragOffsetY = 0;

      final progress = (_dragOffsetY / 300).clamp(0.0, 1.0);
      _dismissScale = 1.0 - (progress * 0.15);
      _dismissOpacity = 1.0 - (progress * 0.6);
      _isDismissing = _dragOffsetY > 20;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;

    if (_dragOffsetY > 120 || velocity > 400) {
      // Dismiss
      Navigator.of(context).pop();
    } else {
      // Snap back
      setState(() {
        _dragOffsetY = 0;
        _dismissScale = 1.0;
        _dismissOpacity = 1.0;
        _isDismissing = false;
      });
    }
  }

  Future<void> _saveMedia() async {
    if (_isSaving) return;
    final url = widget.mediaUrls[_currentIndex];
    final isVid = _isVideo(url);

    setState(() => _isSaving = true);
    try {
      // Download from R2
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Download failed');
      }

      if (isVid) {
        // Save video to temp file, then to gallery
        final dir = await getTemporaryDirectory();
        final ext = url.split('.').last.split('?').first;
        final tempFile = File('${dir.path}/instiy_save_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await tempFile.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(tempFile.path, album: 'instiy');
        await tempFile.delete();
      } else {
        // Save image bytes to gallery
        await Gal.putImageBytes(response.bodyBytes, album: 'instiy');
      }

      // Delete from R2 to free storage
      try {
        await StorageService.deleteImage(url);
      } catch (_) {}

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Saved to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Failed to save'), description: Text('Please try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildImagePage(String url, int index) {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(url),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      initialScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(tag: 'media_$index'),
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      loadingBuilder: (_, _) => const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
      errorBuilder: (_, _, _) => Center(
        child: Icon(LucideIcons.imageOff, color: Colors.white38, size: context.ri(48)),
      ),
    );
  }

  Widget _buildVideoPage(int index) {
    final vc = _videoControllers[index];
    if (vc == null || !vc.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (vc.value.isPlaying) {
              vc.pause();
            } else {
              vc.play();
            }
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: vc.value.aspectRatio,
                child: VideoPlayer(vc),
              ),
            ),
            // Play/pause overlay
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: vc.value.isPlaying
                  ? const SizedBox.shrink(key: ValueKey('playing'))
                  : Container(
                      key: const ValueKey('paused'),
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      padding: context.rAll(16),
                      child: Icon(
                        LucideIcons.play,
                        color: Colors.white,
                        size: context.ri(48),
                      ),
                    ),
            ),
            // Progress bar at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                vc,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppTheme.accent,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
                padding: const EdgeInsets.only(top: 8, bottom: 4),
              ),
            ),
            // Mute/unmute button overlay (only shown when video has audio)
            if (_hasAudioMap[index] ?? true)
              Positioned(
              bottom: context.rh(24),
              right: context.rw(16),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                      color: Colors.white,
                      size: context.ri(24),
                    ),
                    onPressed: () {
                      setState(() {
                        _isMuted = !_isMuted;
                        for (final entry in _videoControllers.entries) {
                          // Only toggle volume on videos that have audio
                          if (_hasAudioMap[entry.key] ?? true) {
                            entry.value.setVolume(_isMuted ? 0.0 : 1.0);
                          }
                        }
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: AnimatedContainer(
          duration: _isDismissing ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          color: Colors.black.withValues(alpha: _dismissOpacity),
          child: Transform.scale(
            scale: _dismissScale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Main page view
                PageView.builder(
                  controller: _pageController,
                  itemCount: widget.mediaUrls.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final url = widget.mediaUrls[index];
                    if (_isVideo(url)) {
                      return _buildVideoPage(index);
                    }
                    return _buildImagePage(url, index);
                  },
                ),

                // Top bar with close and counter
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: padding.top + 8,
                      left: 8,
                      right: 8,
                      bottom: 12,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        ShadIconButton.ghost(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(LucideIcons.x, color: Colors.white, size: context.ri(28)),
                        ),
                        const Spacer(),
                        Container(
                          padding: context.rPadding(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(context.rr(16)),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.mediaUrls.length}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: context.rsp(14),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: _isSaving
                              ? SizedBox(
                                  width: context.rw(24),
                                  height: context.rh(24),
                                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Icon(LucideIcons.ellipsis, color: Colors.white, size: context.ri(28)),
                          onSelected: (value) {
                            if (value == 'save') _saveMedia();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'save',
                              child: Row(
                                children: [
                                  Icon(LucideIcons.download, size: context.ri(18)),
                                  SizedBox(width: context.rw(10)),
                                  Text('Save to Gallery', style: TextStyle(fontSize: context.rsp(14))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
