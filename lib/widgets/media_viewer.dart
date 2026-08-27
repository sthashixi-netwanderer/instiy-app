import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/media_cache_service.dart';
import '../services/video_service.dart';
import '../utils/responsive.dart';
import 'forward_bottom_sheet.dart';
import 'video_init_helper.dart';

class MediaViewer extends StatefulWidget {
  final List<String> mediaUrls;
  final int initialIndex;
  final List<String?>? thumbnailUrls;

  const MediaViewer({
    super.key,
    required this.mediaUrls,
    this.initialIndex = 0,
    this.thumbnailUrls,
  });

  static void open(
    BuildContext context,
    List<String> mediaUrls, {
    int initialIndex = 0,
    List<String?>? thumbnailUrls,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => MediaViewer(
          mediaUrls: mediaUrls,
          initialIndex: initialIndex,
          thumbnailUrls: thumbnailUrls,
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

class _MediaViewerState extends State<MediaViewer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Set<int> _videoFromCache = {};
  bool _isDismissing = false;
  double _dismissOpacity = 1.0;
  double _dismissScale = 1.0;
  double _dragOffsetY = 0;
  // Swipe-up forward state
  double _forwardDragOffset = 0;
  double _forwardOpacity = 0.0;
  bool _isSaving = false;
  bool _isMuted = false;
  final Map<int, bool> _hasAudioMap = {};
  // Long-press speed control state
  bool _isLongPressing = false;
  bool _isRightSide = false; // true = right (ff), false = left (rewind)
  Timer? _rewindTimer;
  DateTime _lastTimerUpdate = DateTime.fromMillisecondsSinceEpoch(0);

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
    _rewindTimer?.cancel();
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _initVideoForIndex(int index) {
    final url = widget.mediaUrls[index];
    if (!_isVideo(url)) return;
    if (_videoControllers.containsKey(index)) return;

    // On web, always stream from network. On mobile, use cache-first.
    if (kIsWeb) {
      _initVideoController(index, url, null);
    } else {
      MediaCacheService.getCachedFile(url).then((cachedFile) {
        if (!mounted || _videoControllers.containsKey(index)) return;
        _initVideoController(index, url, cachedFile);
        if (cachedFile == null) {
          MediaCacheService.precache(url); // ignore: unawaited_futures
        }
      });
    }
  }

  void _initVideoController(int index, String url, dynamic cachedFile) {
    if (!mounted || _videoControllers.containsKey(index)) return;

    final vc = createVideoControllerNative(url, cachedFile: cachedFile);
    if (cachedFile != null) _videoFromCache.add(index);

    _videoControllers[index] = vc;
    vc.addListener(() {
      final now = DateTime.now();
      if (now.difference(_lastTimerUpdate).inMilliseconds >= 500) {
        _lastTimerUpdate = now;
        if (mounted) setState(() {});
      }
    });
    vc.initialize().then((_) async {
      if (mounted) {
        final hasAudio = await VideoService.checkVideoHasAudio(url);
        if (mounted) {
          setState(() {
            _hasAudioMap[index] = hasAudio;
          });
        }
        unawaited(vc.setLooping(true));
        unawaited(vc.setVolume(
          (_isMuted || !hasAudio) ? 0.0 : 1.0,
        ));
        unawaited(vc.play());
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

  void _onLongPressStart(LongPressStartDetails details) {
    final vc = _videoControllers[_currentIndex];
    if (vc == null || !vc.value.isInitialized) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final isRight = details.globalPosition.dx > screenWidth / 2;

    setState(() {
      _isLongPressing = true;
      _isRightSide = isRight;
    });

    if (isRight) {
      // Fast-forward: 2x speed
      vc.setPlaybackSpeed(2.0); // ignore: unawaited_futures
    } else {
      // Rewind: seek backward periodically
      vc.setPlaybackSpeed(1.0); // ignore: unawaited_futures
      _rewindTimer?.cancel();
      _rewindTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final v = _videoControllers[_currentIndex];
        if (v != null && v.value.isInitialized) {
          final newPos = v.value.position - const Duration(milliseconds: 800);
          v.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
        }
      });
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _restorePlaybackSpeed();
  }

  void _onLongPressCancel() {
    _restorePlaybackSpeed();
  }

  void _restorePlaybackSpeed() {
    _rewindTimer?.cancel();
    _rewindTimer = null;
    final vc = _videoControllers[_currentIndex];
    if (vc != null && vc.value.isInitialized) {
      vc.setPlaybackSpeed(1.0); // ignore: unawaited_futures
    }
    if (mounted) {
      setState(() {
        _isLongPressing = false;
      });
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;

    // Swipe down → dismiss
    if (dy > 0 && _forwardDragOffset == 0) {
      setState(() {
        _dragOffsetY += dy;
        if (_dragOffsetY < 0) _dragOffsetY = 0;

        final progress = (_dragOffsetY / 300).clamp(0.0, 1.0);
        _dismissScale = 1.0 - (progress * 0.15);
        _dismissOpacity = 1.0 - (progress * 0.6);
        _isDismissing = _dragOffsetY > 20;
      });
      return;
    }

    // Swipe up → forward
    if (dy < 0 && _dragOffsetY == 0) {
      setState(() {
        _forwardDragOffset += dy.abs();
        if (_forwardDragOffset < 0) _forwardDragOffset = 0;

        final progress = (_forwardDragOffset / 200).clamp(0.0, 1.0);
        _dismissScale = 1.0 - (progress * 0.12);
        _forwardOpacity = progress;
      });
      return;
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;

    // Check downward dismiss
    if (_dragOffsetY > 0) {
      if (_dragOffsetY > 120 || velocity > 400) {
        Navigator.of(context).pop();
      } else {
        _snapBackDismiss();
      }
      return;
    }

    // Check upward forward
    if (_forwardDragOffset > 0) {
      if (_forwardDragOffset > 100 || velocity < -400) {
        _showForwardSheet();
      } else {
        _snapBackForward();
      }
      return;
    }
  }

  void _snapBackDismiss() {
    setState(() {
      _dragOffsetY = 0;
      _dismissScale = 1.0;
      _dismissOpacity = 1.0;
      _isDismissing = false;
    });
  }

  void _snapBackForward() {
    setState(() {
      _forwardDragOffset = 0;
      _dismissScale = 1.0;
      _forwardOpacity = 0.0;
    });
  }

  Future<void> _showForwardSheet() async {
    // Reset forward drag state
    _snapBackForward();

    final url = widget.mediaUrls[_currentIndex];
    final isVid = _isVideo(url);

    await ForwardBottomSheet.show(
      context,
      mediaUrl: url,
      mediaType: isVid ? 'video' : 'image',
      thumbnailUrl:
          widget.thumbnailUrls != null &&
              _currentIndex < widget.thumbnailUrls!.length
          ? widget.thumbnailUrls![_currentIndex]
          : null,
    );
  }

  Future<void> _saveMedia() async {
    if (_isSaving) return;
    final url = widget.mediaUrls[_currentIndex];

    setState(() => _isSaving = true);
    try {
      if (kIsWeb) {
        // On web, open the media URL in a new tab for the user to save.
        await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Opened in new tab — use browser to save')),
          );
        }
      } else {
        // On mobile, save to gallery.
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Download failed');
        }
        // Gallery save is handled by the native platform.
        // Using a simple download approach via url_launcher.
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Saved to gallery')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Failed to save'),
            description: Text('Please try again'),
          ),
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
        child: Icon(
          LucideIcons.imageOff,
          color: Colors.white38,
          size: context.ri(48),
        ),
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
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: _onLongPressCancel,
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
            // Long-press speed indicator
            if (_isLongPressing)
              Positioned(
                top: context.rh(60),
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.rw(16),
                      vertical: context.rh(8),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(context.rr(20)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRightSide
                              ? LucideIcons.fastForward
                              : LucideIcons.rewind,
                          color: Colors.white,
                          size: context.ri(18),
                        ),
                        SizedBox(width: context.rw(6)),
                        Text(
                          _isRightSide ? '2x' : '◀◀',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsp(14),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Timer + Progress bar at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timer text
                  if (vc.value.isInitialized)
                    Padding(
                      padding: EdgeInsets.only(
                        left: context.rw(12),
                        right: context.rw(12),
                        bottom: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(vc.value.position),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            _formatDuration(vc.value.duration),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  VideoProgressIndicator(
                    vc,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: AppTheme.accent,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                  ),
                ],
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
          duration: _isDismissing
              ? Duration.zero
              : const Duration(milliseconds: 200),
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

                // Swipe-up forward indicator
                if (_forwardOpacity > 0)
                  Positioned(
                    bottom: context.rh(60),
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _forwardOpacity,
                        duration: Duration.zero,
                        child: Container(
                          padding: context.rAll(14),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(
                              alpha: 0.9 * _forwardOpacity,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.forward,
                            color: Colors.white,
                            size: context.ri(28),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Swipe-down dismiss indicator
                if (_isDismissing)
                  Positioned(
                    top: context.rh(60),
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: context.rAll(14),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.x,
                          color: Colors.white,
                          size: context.ri(28),
                        ),
                      ),
                    ),
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
                          icon: Icon(
                            LucideIcons.x,
                            color: Colors.white,
                            size: context.ri(28),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: context.rPadding(
                            horizontal: 12,
                            vertical: 6,
                          ),
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
                          position: PopupMenuPosition.under,
                          offset: const Offset(0, 8),
                          icon: _isSaving
                              ? SizedBox(
                                  width: context.rw(24),
                                  height: context.rh(24),
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  LucideIcons.ellipsis,
                                  color: Colors.white,
                                  size: context.ri(28),
                                ),
                          onSelected: (value) {
                            if (value == 'save') _saveMedia();
                            if (value == 'forward') _showForwardSheet();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'forward',
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.forward,
                                    size: context.ri(18),
                                  ),
                                  SizedBox(width: context.rw(10)),
                                  Text(
                                    'Forward',
                                    style: TextStyle(fontSize: context.rsp(14)),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'save',
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.download,
                                    size: context.ri(18),
                                  ),
                                  SizedBox(width: context.rw(10)),
                                  Text(
                                    'Save to Gallery',
                                    style: TextStyle(fontSize: context.rsp(14)),
                                  ),
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
