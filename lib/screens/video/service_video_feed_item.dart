import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../models/service_model.dart';
import '../../providers/providers.dart';
import '../../services/follow_service.dart';
import '../../services/media_cache_service.dart';
import '../../services/video_service.dart';
import '../../services/service_service.dart';
import '../../widgets/instiy_logo_placeholder.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/video_init_helper.dart';
import '../../widgets/video_watermark_overlay.dart';
import '../../utils/bold_text.dart';
import '../../utils/responsive.dart';
import '../../utils/share_helper.dart';
import 'package:instiy/utils/formatters.dart';

/// One service clip in the feed. Mirrors [VideoFeedItem] but is driven by a
/// [Service]: a horizontal right-to-left swipe opens the service detail
/// screen (product clips open the seller's public store instead), and there
/// is no product-like/favorites interaction — services have no favorites.
class ServiceVideoFeedItem extends ConsumerStatefulWidget {
  final Service service;
  final bool isActive;
  final ValueNotifier<bool> canPlay;

  const ServiceVideoFeedItem({
    super.key,
    required this.service,
    required this.isActive,
    required this.canPlay,
  });

  @override
  ConsumerState<ServiceVideoFeedItem> createState() =>
      _ServiceVideoFeedItemState();
}

class _ServiceVideoFeedItemState extends ConsumerState<ServiceVideoFeedItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followerCount = 0;
  bool _isMuted = false;
  bool _hasAudio = true;
  int _reviewCount = 0;
  bool _isDescriptionExpanded = false;
  String? _speedText;
  bool _showSpeedIndicator = false;

  /// TikTok-style long-press zones: holding the left/right edge rewinds /
  /// fast-forwards while held, holding the center keeps the video paused
  /// until release. Only one hold is active at a time.
  Timer? _holdSeekTimer;
  bool _holdingPause = false;
  bool _wasPlayingBeforeHold = false;

  bool get _isOwnService {
    final userId = ref.read(authProvider).user?.id;
    return userId != null && userId == widget.service.providerId;
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initVideo();
    }
    _loadFollowStatus();
    _loadCounts();
    widget.canPlay.addListener(_onCanPlayChanged);
  }

  @override
  void didUpdateWidget(covariant ServiceVideoFeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.canPlay != oldWidget.canPlay) {
      oldWidget.canPlay.removeListener(_onCanPlayChanged);
      widget.canPlay.addListener(_onCanPlayChanged);
    }
    if (widget.isActive && !oldWidget.isActive) {
      _initVideo();
    } else if (!widget.isActive && oldWidget.isActive) {
      _disposeVideo();
    }
  }

  void _onCanPlayChanged() {
    if (!widget.canPlay.value) {
      _forcePause();
    } else if (widget.isActive) {
      _resumeVideo();
    }
  }

  /// Forceful pause for leaving the screen: drops any press-and-hold
  /// (seek timer, 2x speed, pause-hold), restores normal speed, hides the
  /// scrub indicator, and pauses — so no clip keeps running in the
  /// background no matter what state it was in.
  void _forcePause() {
    _cancelHold();
    if (_controller != null && _isInitialized) {
      _controller!.setPlaybackSpeed(1.0); // ignore: unawaited_futures
    }
    if (mounted) {
      setState(() {
        _speedText = null;
        _showSpeedIndicator = false;
      });
    }
    _pauseVideo();
  }

  @override
  void dispose() {
    _cancelHold();
    widget.canPlay.removeListener(_onCanPlayChanged);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    if (_controller != null && _isInitialized) {
      // Only autoplay when the feed is actually on screen — the user may
      // have navigated away while this item was being rebuilt.
      if (!widget.canPlay.value) return;
      _controller!.play(); // ignore: unawaited_futures
      setState(() {
        _isPlaying = true;
        _isMuted = false;
      });
      _controller!.setVolume(_hasAudio ? 1.0 : 0.0); // ignore: unawaited_futures
      return;
    }
    if (widget.service.videoUrls.isEmpty) return;
    // Guard against overlapping init calls (e.g. quick inactive→active flips
    // while a previous initialization is still awaiting the cache lookup).
    if (_isInitializing) return;
    _isInitializing = true;

    final videoUrl =
        widget.service.clipVideoUrl ?? widget.service.videoUrls.first;

    try {
      // Cache-first on mobile: start instantly from a previously downloaded
      // (prefetched) copy; otherwise stream from network and warm the cache in
      // the background so the next view of this clip is instant. Web always
      // streams from network.
      if (kIsWeb) {
        _controller = createVideoControllerNative(videoUrl);
      } else {
        final cachedFile = await MediaCacheService.getCachedFile(videoUrl);
        if (!mounted) return;
        _controller = createVideoControllerNative(videoUrl, cachedFile: cachedFile);
        if (cachedFile == null) {
          MediaCacheService.precache(videoUrl); // ignore: unawaited_futures
        }
      }

      await _controller!.initialize();
      _controller!.setLooping(true); // ignore: unawaited_futures

      // Check if video has audio track
      final hasAudio = await VideoService.checkVideoHasAudio(videoUrl);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasAudio = hasAudio;
          _isMuted = !hasAudio; // auto-mute if no audio
        });
        _controller!.setVolume(hasAudio ? 1.0 : 0.0); // ignore: unawaited_futures
        // initialize() can complete after the user has already navigated
        // away — never start playback unless the feed is on screen.
        if (widget.isActive && widget.canPlay.value) {
          _controller!.play(); // ignore: unawaited_futures
          setState(() => _isPlaying = true);
        }
      }
    } catch (e) {
      debugPrint('Error initializing service video player: $e');
    } finally {
      _isInitializing = false;
    }
  }

  void _disposeVideo() {
    _cancelHold();
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isPlaying = false;
        });
      }
    }
  }

  void _pauseVideo() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _resumeVideo() {
    if (_controller == null || !_isInitialized) {
      _initVideo();
      return;
    }
    if (!_controller!.value.isPlaying) {
      _controller!.play();
      if (mounted) {
        setState(() => _isPlaying = true);
        _controller!.setVolume(_hasAudio ? 1.0 : 0.0);
      }
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  /// Starts a press-and-hold gesture, zoned by horizontal position:
  /// outer thirds scrub (left rewinds, right fast-forwards) while the
  /// middle third holds the video paused until release.
  void _startHold(double dx, double width) {
    if (!_isInitialized || _controller == null) return;
    _wasPlayingBeforeHold = _controller!.value.isPlaying;
    if (dx < width / 3) {
      _holdSeekTimer =
          Timer.periodic(const Duration(milliseconds: 250), (_) {
        final c = _controller;
        if (c == null || !_isInitialized || !mounted) return;
        final back = c.value.position - const Duration(seconds: 3);
        c.seekTo(back > Duration.zero ? back : Duration.zero); // ignore: unawaited_futures
      });
      setState(() {
        _speedText = '↩';
        _showSpeedIndicator = true;
      });
    } else if (dx > width * 2 / 3) {
      _controller!.setPlaybackSpeed(2.0); // ignore: unawaited_futures
      setState(() {
        _speedText = '2x';
        _showSpeedIndicator = true;
      });
    } else {
      _holdingPause = true;
      if (_controller!.value.isPlaying) {
        _controller!.pause(); // ignore: unawaited_futures
        if (mounted) setState(() => _isPlaying = false);
      }
    }
  }

  /// Releases a press-and-hold: stops scrubbing, restores speed, and
  /// resumes only when the hold itself paused a playing video.
  void _endHold() {
    _holdSeekTimer?.cancel();
    _holdSeekTimer = null;
    if (_controller != null && _isInitialized) {
      _controller!.setPlaybackSpeed(1.0); // ignore: unawaited_futures
    }
    final resume = _holdingPause && _wasPlayingBeforeHold;
    _holdingPause = false;
    _wasPlayingBeforeHold = false;
    if (mounted) {
      setState(() {
        _speedText = null;
        _showSpeedIndicator = false;
      });
    }
    if (resume) _resumeVideo();
  }

  /// Drops hold state without resuming (page swiped away, video disposed).
  void _cancelHold() {
    _holdSeekTimer?.cancel();
    _holdSeekTimer = null;
    _holdingPause = false;
    _wasPlayingBeforeHold = false;
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  Future<void> _loadFollowStatus() async {
    if (widget.service.providerId.isEmpty) return;
    final userId = ref.read(authProvider).user?.id;
    try {
      final count = await FollowService.getFollowerCount(widget.service.providerId);
      if (mounted) setState(() => _followerCount = count);

      if (userId != null && userId != widget.service.providerId) {
        final following = await FollowService.isFollowing(widget.service.providerId);
        if (mounted) setState(() => _isFollowing = following);
      }
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    try {
      final reviews = await ServiceService.getServiceReviews(widget.service.id);
      if (mounted) setState(() => _reviewCount = reviews.length);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      Navigator.of(context).pushNamed('/login'); // ignore: unawaited_futures
      return;
    }
    if (userId == widget.service.providerId) {
      return;
    }
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await FollowService.unfollow(widget.service.providerId);
        if (mounted) {
          setState(() {
            _isFollowing = false;
            if (_followerCount > 0) _followerCount--;
          });
        }
      } else {
        await FollowService.follow(widget.service.providerId);
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followerCount++;
          });
          ShadToaster.of(context).show(
            const ShadToast(title: Text('You are now following this seller')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  String get _shareText {
    final s = widget.service;
    return 'Check out "${BoldText.convert(s.title)}" on Instiy - ${formatGhs(s.startingPrice)}';
  }

  void _openServiceDetail() {
    Navigator.of(context).pushNamed('/service-detail', arguments: widget.service.id);
  }

  @override
  Widget build(BuildContext context) {
    // Swiping right-to-left on a service clip opens its detail screen
    // (product clips open the seller's public store).
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
          _openServiceDetail();
        }
      },
      child: Stack(
        children: [
          // Video Player Background
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlayPause,
              onLongPressStart: (details) {
                _startHold(
                  details.localPosition.dx,
                  MediaQuery.of(context).size.width,
                );
              },
              onLongPressEnd: (_) => _endHold(),
              onLongPressCancel: _cancelHold,
              child: Container(
                color: Colors.black,
                child: _isInitialized && _controller != null
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : widget.service.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.service.imageUrls.first,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            placeholder: (context, url) => const InstiyLogoPlaceholder(
                              width: double.infinity,
                              height: double.infinity,
                            ),
                            errorWidget: (context, url, error) => const InstiyLogoPlaceholder(
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          )
                        : const InstiyLogoPlaceholder(
                            width: double.infinity,
                            height: double.infinity,
                          ),
              ),
            ),
          ),

          // Video watermark — subtle attribution on the clip itself
          if (_isInitialized)
            Positioned(
              left: 16,
              top: MediaQuery.of(context).padding.top + 52,
              child: VideoWatermarkOverlay(
                storeName: widget.service.providerName ?? 'Instiy',
              ),
            ),

          // Speed/Seek overlay indicator
          if (_showSpeedIndicator && _speedText != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _speedText!.contains('2x') ? AppTheme.accent.withValues(alpha: 0.85) : Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _speedText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Play/Pause Overlay indicator
          if (!_isPlaying && _isInitialized)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.play,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),

          // Mute button — top right (only shown when video has audio)
          if (_isInitialized && _hasAudio)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 16,
              child: GestureDetector(
                onTap: _toggleMute,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isMuted ? Colors.white24 : Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: _isMuted ? Colors.white38 : Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),

          // Right side overlays
          Positioned(
            right: 16,
            bottom: 120,
            child: Column(
              children: [
                _buildProviderAvatar(),
                const SizedBox(height: 20),
                _buildOverlayIconButton(
                  icon: Icons.chat_bubble,
                  color: Colors.white,
                  label: _reviewCount > 0 ? _formatCount(_reviewCount) : 'Reviews',
                  onTap: _openServiceDetail,
                ),
                const SizedBox(height: 20),
                _buildOverlayIconButton(
                  icon: LucideIcons.share2,
                  color: Colors.white,
                  label: 'Share',
                  onTap: () {
                    ShareHelper.shareText(
                      _shareText,
                      context: context,
                    ); // ignore: unawaited_futures
                  },
                ),
              ],
            ),
          ),

          // Bottom overlays (Provider name, service description, CTA)
          Positioned(
            left: 16,
            right: 80,
            bottom: 110, // Avoid bottom navigation overlap
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider Info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () {
                          if (widget.service.providerId.isNotEmpty) {
                            Navigator.of(context).pushNamed(
                              '/business-profile',
                              arguments: widget.service.providerId,
                            );
                          }
                        },
                        child: Text(
                          '@${widget.service.providerName ?? 'provider'}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsp(16),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (widget.service.providerIsVerified) ...[
                      const SizedBox(width: 6),
                      VerificationBadge(size: 14),
                    ],
                    // Only show the Follow button while NOT following. Once the
                    // user follows the provider, the button is hidden entirely on
                    // the clips screen (no "Following" state shown here).
                    if (!_isOwnService && !_isFollowing) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '•',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _isFollowLoading ? () {} : _toggleFollow,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppTheme.accent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _isFollowLoading ? '...' : 'Follow',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: context.rsp(11),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Service Info
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.65),
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.service.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: context.rsp(14),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (widget.service.description != null &&
                          widget.service.description!.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(
                              () => _isDescriptionExpanded = !_isDescriptionExpanded),
                          child: Text(
                            widget.service.description!,
                            maxLines: _isDescriptionExpanded ? null : 2,
                            overflow: _isDescriptionExpanded
                                ? null
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: context.rsp(13),
                            ),
                          ),
                        ),
                      if (!_isDescriptionExpanded &&
                          (widget.service.description?.length ?? 0) > 80)
                        GestureDetector(
                          onTap: () => setState(() => _isDescriptionExpanded = true),
                          child: Text(
                            'more',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Price & CTA Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'From ${formatGhs(widget.service.startingPrice)}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.rsp(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _openServiceDetail,
                      child: const Text(
                        'View Service',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Video Progress bar
          if (_isInitialized && _controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppTheme.accent,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProviderAvatar() {
    return GestureDetector(
      onTap: () {
        if (widget.service.providerId.isNotEmpty) {
          Navigator.of(context).pushNamed(
            '/business-profile',
            arguments: widget.service.providerId,
          );
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.accent,
              backgroundImage: widget.service.providerAvatar != null &&
                      widget.service.providerAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.service.providerAvatar!)
                  : null,
              child: widget.service.providerAvatar == null ||
                      widget.service.providerAvatar!.isEmpty
                  ? Text(
                      (widget.service.providerName ?? 'U').isNotEmpty
                          ? (widget.service.providerName ?? 'U')[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.plus,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildOverlayIconButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
