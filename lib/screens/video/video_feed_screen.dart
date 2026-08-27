import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/follow_service.dart';
import '../../services/media_cache_service.dart';
import '../../services/video_analytics_service.dart';
import '../../services/video_service.dart';
import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';
import '../../models/seller_review_model.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/instiy_logo_placeholder.dart';
import '../../widgets/review_section.dart';
import '../../widgets/verification_badge.dart';
import '../../utils/share_helper.dart';
import '../../widgets/video_init_helper.dart';
import '../../widgets/video_watermark_overlay.dart';
import '../../utils/bold_text.dart';
import '../../utils/responsive.dart';
import 'package:instiy/utils/formatters.dart';

class VideoFeedScreen extends ConsumerStatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  ConsumerState<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends ConsumerState<VideoFeedScreen> with WidgetsBindingObserver, RouteAware {
  late final PageController _pageController;
  final ValueNotifier<bool> _canPlay = ValueNotifier(true);
  ProviderSubscription<List<Product>>? _productsSub;
  ProviderSubscription<int>? _focusedIndexSub;
  ProviderSubscription<int>? _shellTabSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialPage = ref.read(videoProvider).focusedIndex;
    _pageController = PageController(initialPage: initialPage);
    // Warm the cache for the next two clips whenever the feed reloads or the
    // user pages forward, so swiping to the next video starts instantly.
    _productsSub = ref.listenManual(
      videoProvider.select((v) => v.products),
      (previous, next) {
        _syncPageAfterClipRemoval(previous, next);
        _prefetchUpcomingClips();
      },
    );
    _focusedIndexSub = ref.listenManual(
      videoProvider.select((v) => v.focusedIndex),
      (previous, next) => _prefetchUpcomingClips(),
    );
    // Inside the navigation shell, tab switches don't fire route events —
    // pause playback directly when the Clips tab is left.
    _shellTabSub = ref.listenManual(shellTabProvider, (previous, next) {
      _canPlay.value = next == 2 && (ModalRoute.of(context)?.isCurrent ?? true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoProvider).ensureInitialized();
      // Covers the already-initialized case; a fresh load triggers the
      // products listener above.
      _prefetchUpcomingClips();
    });
  }

  /// Downloads the video files of the next two clips after the focused one.
  /// no-op on web (web streams directly from network).
  void _prefetchUpcomingClips() {
    final videoState = ref.read(videoProvider);
    final products = videoState.products;
    final first = videoState.focusedIndex + 1;
    for (var i = first; i < first + 2 && i < products.length; i++) {
      final url = products[i].clipVideoUrl ??
          (products[i].videoUrls.isNotEmpty ? products[i].videoUrls.first : null);
      if (url != null && url.isNotEmpty) {
        MediaCacheService.precache(url); // ignore: unawaited_futures
      }
    }
  }

  /// When a clip is deleted in realtime, the provider removes it and shifts
  /// the focused index so it keeps pointing at the video the user is watching.
  /// The PageController still sits on the old page, so nudge it to match.
  void _syncPageAfterClipRemoval(List<Product>? previous, List<Product> next) {
    if (next.length >= (previous?.length ?? next.length)) return;
    if (!_pageController.hasClients) return;
    final focused = ref.read(videoProvider).focusedIndex;
    if (_pageController.page?.round() != focused) {
      _pageController.jumpToPage(focused);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      NavigationService.routeObserver.subscribe(this, route);
      _canPlay.value = route.isCurrent;
    }
  }

  @override
  void didPush() {
    _canPlay.value = true;
  }

  @override
  void didPopNext() {
    _canPlay.value = true;
  }

  @override
  void didPushNext() {
    _canPlay.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _canPlay.value = false;
    } else if (state == AppLifecycleState.resumed) {
      final route = ModalRoute.of(context);
      _canPlay.value = route?.isCurrent ?? false;
    }
  }

  @override
  void dispose() {
    NavigationService.routeObserver.unsubscribe(this);
    _canPlay.value = false;
    WidgetsBinding.instance.removeObserver(this);
    _productsSub?.close();
    _focusedIndexSub?.close();
    _shellTabSub?.close();
    _canPlay.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoState = ref.watch(videoProvider);
    final products = videoState.products;
    final isLoading = videoState.isLoading;
    final focusedIndex = videoState.focusedIndex;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      bottomNavigationBar: AdaptiveNav(
        currentIndex: ref.watch(shellTabProvider),
        onTabSelected: (i) => ref.read(shellTabProvider.notifier).state = i,
      ),
      body: isLoading
          ? const VideoFeedSkeleton()
          : products.isEmpty
              ? _buildEmptyState()
              : NotificationListener<OverscrollNotification>(
                  onNotification: (notification) {
                    // Pulling down past the top of the first video refreshes
                    // the feed (debounced).
                    if (notification.overscroll < 0 && focusedIndex == 0) {
                      _maybeRefreshFeed();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    // Pre-builds the adjacent pages so the next clip's UI is
                    // ready before the user swipes to it.
                    allowImplicitScrolling: true,
                    itemCount: products.length,
                    onPageChanged: (index) {
                      ref.read(videoProvider).setFocusedIndex(index);
                    },
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return VideoFeedItem(
                        key: ValueKey(product.id),
                        product: product,
                        isActive: index == focusedIndex,
                        canPlay: _canPlay,
                      );
                    },
                  ),
                ),
    );
  }

  DateTime? _lastFeedRefreshAt;

  void _maybeRefreshFeed() {
    final now = DateTime.now();
    if (_lastFeedRefreshAt != null &&
        now.difference(_lastFeedRefreshAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastFeedRefreshAt = now;
    ref.read(videoProvider).refresh();
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () => ref.read(videoProvider).loadVideos(silent: false),
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.videoOff,
                  size: context.ri(64),
                  color: Colors.white30,
                ),
                const SizedBox(height: 16),
                Text(
                  'No video clips yet',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: context.rsp(18),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check back later or upload a listing with video',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: context.rsp(14),
                  ),
                ),
                const SizedBox(height: 24),
                ShadButton(
                  onPressed: () => ref.read(videoProvider).loadVideos(silent: false),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoFeedItem extends ConsumerStatefulWidget {
  final Product product;
  final bool isActive;
  final ValueNotifier<bool> canPlay;

  const VideoFeedItem({
    super.key,
    required this.product,
    required this.isActive,
    required this.canPlay,
  });

  @override
  ConsumerState<VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends ConsumerState<VideoFeedItem> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _showHeartAnimation = false;
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followerCount = 0;
  bool _isMuted = false;
  bool _hasAudio = true;
  int _likeCount = 0;
  int _reviewCount = 0;
  bool _isDescriptionExpanded = false;
  String? _speedText;
  bool _showSpeedIndicator = false;

  bool get _isOwnProduct {
    final userId = ref.read(authProvider).user?.id;
    return userId != null && userId == widget.product.sellerId;
  }

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heartScale = Tween<double>(begin: 0.5, end: 1.2).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.elasticOut),
    );

    if (widget.isActive) {
      _initVideo();
    }
    _loadFollowStatus();
    _loadCounts();
    widget.canPlay.addListener(_onCanPlayChanged);
  }

  @override
  void didUpdateWidget(covariant VideoFeedItem oldWidget) {
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
      _pauseVideo();
    } else if (widget.isActive) {
      _resumeVideo();
    }
  }

  @override
  void dispose() {
    widget.canPlay.removeListener(_onCanPlayChanged);
    _controller?.dispose();
    _heartController.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    if (_controller != null && _isInitialized) {
      _controller!.play(); // ignore: unawaited_futures
      setState(() {
        _isPlaying = true;
        _isMuted = false;
      });
      _controller!.setVolume(_hasAudio ? 1.0 : 0.0); // ignore: unawaited_futures
      if (!_isOwnProduct) {
        VideoAnalyticsService.recordView(widget.product.id); // ignore: unawaited_futures
      }
      return;
    }
    if (widget.product.videoUrls.isEmpty) return;
    // Guard against overlapping init calls (e.g. quick inactive→active flips
    // while a previous initialization is still awaiting the cache lookup).
    if (_isInitializing) return;
    _isInitializing = true;

    final videoUrl = widget.product.clipVideoUrl ?? widget.product.videoUrls.first;

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
        if (widget.isActive) {
          _controller!.play(); // ignore: unawaited_futures
          setState(() => _isPlaying = true);
          if (!_isOwnProduct) {
            VideoAnalyticsService.recordView(widget.product.id); // ignore: unawaited_futures
          }
        }
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    } finally {
      _isInitializing = false;
    }
  }

  void _disposeVideo() {
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

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _handleDoubleTap() {
    if (_isOwnProduct) return;
    final prodProv = ref.read(productProvider);
    if (!prodProv.isFavorited(widget.product.id)) {
      prodProv.toggleFavorite(widget.product.id);
    }

    setState(() => _showHeartAnimation = true);
    _heartController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() => _showHeartAnimation = false);
        }
      });
    });
  }

  Future<void> _loadFollowStatus() async {
    if (widget.product.sellerId.isEmpty) return;
    final userId = ref.read(authProvider).user?.id;
    try {
      final count = await FollowService.getFollowerCount(widget.product.sellerId);
      if (mounted) setState(() => _followerCount = count);

      if (userId != null && userId != widget.product.sellerId) {
        final following = await FollowService.isFollowing(widget.product.sellerId);
        if (mounted) setState(() => _isFollowing = following);
      }
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    try {
      final likeResponse = await SupabaseService.table('favorites')
          .select()
          .eq('product_id', widget.product.id)
          .count();
      final reviews = await ReviewService.getProductReviews(widget.product.id);

      if (mounted) {
        setState(() {
          _likeCount = likeResponse.count;
          _reviewCount = reviews.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      Navigator.of(context).pushNamed('/login'); // ignore: unawaited_futures
      return;
    }
    if (userId == widget.product.sellerId) {
      return;
    }
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await FollowService.unfollow(widget.product.sellerId);
        if (mounted) {
          setState(() {
            _isFollowing = false;
            if (_followerCount > 0) _followerCount--;
          });
        }
      } else {
        await FollowService.follow(widget.product.sellerId);
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

  Future<void> _toggleLike() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      Navigator.of(context).pushNamed('/login'); // ignore: unawaited_futures
      return;
    }
    final prodProv = ref.read(productProvider);
    final wasLiked = prodProv.isFavorited(widget.product.id);
    await prodProv.toggleFavorite(widget.product.id);
    if (!mounted) return;
    final isLiked = prodProv.isFavorited(widget.product.id);
    if (isLiked == wasLiked) return;
    setState(() {
      if (isLiked) {
        _likeCount++;
      } else if (_likeCount > 0) {
        _likeCount--;
      }
    });
  }

  String get _shareText {
    final p = widget.product;
    return 'Check out "${BoldText.convert(p.title)}" on Instiy - ${formatGhs(p.effectivePrice)}\n\nLink: https://instiy.com/products/${p.slug}-${p.id}';
  }

  @override
  Widget build(BuildContext context) {
    final prodProv = ref.watch(productProvider);
    final isLiked = prodProv.isFavorited(widget.product.id);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
          if (widget.product.sellerId.isNotEmpty) {
            Navigator.of(context).pushNamed(
              '/business-profile',
              arguments: widget.product.sellerId,
            );
          }
        }
      },
      child: Stack(
      children: [
        // Video Player Background
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlayPause,
            onDoubleTap: _handleDoubleTap,
            onLongPressStart: (details) {
              if (!_isInitialized || _controller == null) return;
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.localPosition.dx > screenWidth / 2) {
                _controller!.setPlaybackSpeed(2.0);
                setState(() { _speedText = '2x'; _showSpeedIndicator = true; });
              } else {
                final current = _controller!.value.position;
                final newPos = current - const Duration(seconds: 10);
                _controller!.seekTo(newPos > Duration.zero ? newPos : Duration.zero);
                setState(() { _speedText = '\u21A9 10s'; _showSpeedIndicator = true; });
              }
            },
            onLongPressEnd: (_) {
              if (_controller != null && _isInitialized) {
                _controller!.setPlaybackSpeed(1.0);
              }
              setState(() { _speedText = null; _showSpeedIndicator = false; });
            },
            child: Container(
              color: Colors.black,
              child: _isInitialized && _controller != null
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : widget.product.effectiveThumbnail != null
                      ? CachedNetworkImage(
                          imageUrl: widget.product.effectiveThumbnail!,
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
              storeName: widget.product.businessName ?? widget.product.sellerName,
            ),
          ),

        // Double-tap heart pop animation
        if (_showHeartAnimation)
          Center(
            child: ScaleTransition(
              scale: _heartScale,
              child: const Icon(
                Icons.favorite,
                color: Colors.red,
                size: 100,
              ),
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
              _buildSellerAvatar(),
              if (!_isOwnProduct) ...[
                const SizedBox(height: 20),
                _buildOverlayIconButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.white,
                  label: _likeCount > 0 ? _formatCount(_likeCount) : 'Like',
                  onTap: _toggleLike,
                ),
              ],
              const SizedBox(height: 20),
              _buildOverlayIconButton(
                icon: Icons.chat_bubble,
                color: Colors.white,
                label: _reviewCount > 0 ? _formatCount(_reviewCount) : 'Reviews',
                onTap: _showCommentsSheet,
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

        // Bottom overlays (Seller Name, Product description, Buy CTA)
        Positioned(
          left: 16,
          right: 80,
          bottom: 110, // Avoid bottom navigation overlap
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seller Info
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () {
                        if (widget.product.sellerId.isNotEmpty) {
                          Navigator.of(context).pushNamed(
                            '/business-profile',
                            arguments: widget.product.sellerId,
                          );
                        }
                      },
                      child: Text(
                        '@${widget.product.businessName ?? widget.product.sellerName ?? 'seller'}',
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
                  if (widget.product.isSellerVerified) ...[
                    const SizedBox(width: 6),
                    VerificationBadge(size: 14),
                  ],
                  // Only show the Follow button while NOT following. Once the
                  // user follows the seller, the button is hidden entirely on
                  // the clips screen (no "Following" state shown here).
                  if (!_isOwnProduct && !_isFollowing) ...[
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

              // Product Info
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
                      widget.product.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: context.rsp(14),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                      child: Text(
                        _isDescriptionExpanded
                            ? widget.product.description
                            : widget.product.description,
                        maxLines: _isDescriptionExpanded ? null : 2,
                        overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: context.rsp(13),
                        ),
                      ),
                    ),
                    if (!_isDescriptionExpanded && widget.product.description.length > 80)
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
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formatGhs(widget.product.effectivePrice),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: context.rsp(14),
                          ),
                        ),
                      ),
                      if (widget.product.isDiscountActive)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
                            ),
                            child: Text(
                              '-${formatCurrency(widget.product.discountPercent)}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: context.rsp(9),
                              ),
                            ),
                          ),
                        ),
                    ],
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
                    onPressed: () {
                      Navigator.of(context).pushNamed(
                        '/product',
                        arguments: widget.product.id,
                      );
                    },
                    child: const Text(
                      'View Product',
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

  Widget _buildSellerAvatar() {
    return GestureDetector(
      onTap: () {
        if (widget.product.sellerId.isNotEmpty) {
          Navigator.of(context).pushNamed(
            '/business-profile',
            arguments: widget.product.sellerId,
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
              backgroundImage: widget.product.sellerAvatar != null && widget.product.sellerAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.product.sellerAvatar!)
                  : null,
              child: widget.product.sellerAvatar == null || widget.product.sellerAvatar!.isEmpty
                  ? Text(
                      (widget.product.businessName ?? widget.product.sellerName ?? 'U').isNotEmpty
                          ? (widget.product.businessName ?? widget.product.sellerName ?? 'U')[0].toUpperCase()
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

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CommentsBottomSheet(
        productId: widget.product.id,
        onReviewAdded: _loadCounts,
      ),
    );
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

/// Full-screen placeholder while the clip feed loads — dark backdrop matching
/// the video surface with a breathing Instiy logo.
class VideoFeedSkeleton extends StatelessWidget {
  const VideoFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const InstiyLogoPlaceholder(
      width: double.infinity,
      height: double.infinity,
      animate: true,
      backgroundColor: Colors.black,
      logoColor: AppTheme.whisperBorder,
    );
  }
}

class _CommentsBottomSheet extends ConsumerStatefulWidget {
  final String productId;
  final VoidCallback onReviewAdded;

  const _CommentsBottomSheet({
    required this.productId,
    required this.onReviewAdded,
  });

  @override
  ConsumerState<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends ConsumerState<_CommentsBottomSheet> {
  List<ProductReview> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await ReviewService.getProductReviews(widget.productId);
      if (mounted) setState(() { _reviews = reviews; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_reviews.length} ${_reviews.length == 1 ? 'Review' : 'Reviews'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                      : _reviews.isEmpty
                          ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No reviews yet. Be the first to review this product!',
                              style: TextStyle(color: AppTheme.mutedSteel, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _reviews.length,
                          itemBuilder: (context, index) {
                            final userId = ref.read(authProvider).user?.id;
                            return _CommentItem(
                              review: _reviews[index],
                              isOwn: _reviews[index].reviewerId == userId,
                              onUpdated: _loadReviews,
                            );
                          },
                        ),
            ),
            // Review composer — same form the product detail screen uses:
            // rating starts unselected (required) and supports up to 5
            // attached photos/videos.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppTheme.whisperBorder),
                ),
              ),
              child: ReviewForm(
                productId: widget.productId,
                onSubmitted: () {
                  widget.onReviewAdded();
                  _loadReviews();
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  final ProductReview review;
  final bool isOwn;
  final VoidCallback onUpdated;

  const _CommentItem({
    required this.review,
    this.isOwn = false,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.warmMist,
            backgroundImage: review.reviewerAvatar != null && review.reviewerAvatar!.isNotEmpty
                ? CachedNetworkImageProvider(review.reviewerAvatar!)
                : null,
            child: review.reviewerAvatar == null || review.reviewerAvatar!.isEmpty
                ? Icon(Icons.person, color: AppTheme.mutedSteel, size: 18)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      review.reviewerName ?? 'Anonymous',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(review.createdAt),
                      style: TextStyle(color: AppTheme.mutedSteel, fontSize: 11),
                    ),
                    if (isOwn) ...[
                      const Spacer(),
                      PopupMenuButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.more_vert, size: 16, color: AppTheme.mutedSteel),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(fontSize: 14))),
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontSize: 14))),
                        ],
                        onSelected: (v) async {
                          if (v == 'edit') {
                            showShadSheet( // ignore: unawaited_futures
                              context: context,
                              builder: (ctx) => ShadSheet(
                                title: const Text('Edit Your Review'),
                                child: ReviewForm(
                                  productId: review.productId,
                                  existing: review,
                                  onSubmitted: () {
                                    Navigator.of(ctx).pop();
                                    onUpdated();
                                  },
                                ),
                              ),
                            );
                          } else if (v == 'delete') {
                            final confirmed = await AppTheme.showGlassDialog<bool>(
                              context: context,
                              title: const Text('Delete Review'),
                              description: const Text('Are you sure you want to delete this review? This cannot be undone.'),
                              actions: [
                                ShadButton.ghost(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                ShadButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            );
                            if (confirmed == true) {
                              await ReviewService.deleteReview(review.id);
                              onUpdated();
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    color: AppTheme.warningAmber,
                    size: 12,
                  )),
                ),
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.comment!,
                    style: const TextStyle(fontSize: 13, color: AppTheme.charcoalInk),
                  ),
                ],
                // Attached review photos/videos
                if (review.mediaUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: review.mediaUrls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final url = review.mediaUrls[i];
                        final isVideo =
                            url.contains('.mp4') || url.contains('.mov');
                        return GestureDetector(
                          onTap: () =>
                              _showMediaViewer(context, review.mediaUrls, i),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: AppTheme.warmMist,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: isVideo
                                ? const Center(
                                    child: Icon(LucideIcons.video,
                                        size: 24,
                                        color: AppTheme.mutedSteel),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 160,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaViewer(BuildContext context, List<String> urls, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: PageView.builder(
          itemCount: urls.length,
          controller: PageController(initialPage: initialIndex),
          itemBuilder: (context, i) {
            final url = urls[i];
            final isVideo = url.contains('.mp4') || url.contains('.mov');
            return InteractiveViewer(
              child: isVideo
                  ? const Center(
                      child: Icon(LucideIcons.video,
                          size: 48, color: Colors.white54),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                    ),
            );
          },
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}
