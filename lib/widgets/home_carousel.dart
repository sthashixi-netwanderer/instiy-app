import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/carousel_slide_model.dart';
import '../models/product_model.dart';
import 'discount_countdown.dart';

class HomeCarousel extends StatefulWidget {
  final List<CarouselSlide> slides;
  final Map<String, Product> linkedProducts;
  final void Function(CarouselSlide slide)? onButtonTap;

  const HomeCarousel({
    super.key,
    required this.slides,
    this.linkedProducts = const {},
    this.onButtonTap,
  });

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> with WidgetsBindingObserver {
  late PageController _pageController;
  Timer? _autoPlayTimer;
  int _currentPage = 0;
  bool _userInteracting = false;

  // Video controllers — lazy init, keep only current + neighbors
  final Map<int, VideoPlayerController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(viewportFraction: 0.92);
    _initCurrentVideo();
    _startAutoPlay();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _autoPlayTimer?.cancel();
      _pauseAllVideos();
    } else if (state == AppLifecycleState.resumed) {
      _startAutoPlay();
      _playCurrentVideo();
    }
  }

  @override
  void didUpdateWidget(HomeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length ||
        oldWidget.linkedProducts.length != widget.linkedProducts.length ||
        (oldWidget.slides.isNotEmpty &&
            widget.slides.isNotEmpty &&
            oldWidget.slides.first.id != widget.slides.first.id)) {
      _currentPage = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _disposeAllVideos();
      _initCurrentVideo();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    _disposeAllVideos();
    super.dispose();
  }

  // --- Video management ---

  void _disposeAllVideos() {
    for (final c in _videoControllers.values) {
      c.dispose();
    }
    _videoControllers.clear();
  }

  void _initCurrentVideo() {
    if (widget.slides.isEmpty) return;
    final slide = widget.slides[_currentPage];
    if (slide.isVideo && !_videoControllers.containsKey(_currentPage)) {
      _initVideoController(_currentPage, slide);
    }
  }

  Future<void> _initVideoController(int index, CarouselSlide slide) async {
    if (_videoControllers.containsKey(index)) return;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(slide.mediaUrl));
      _videoControllers[index] = controller;
      await controller.initialize();
      unawaited(controller.setVolume(0)); // muted by default
      unawaited(controller.setLooping(false)); // no loop — we advance on completion
      controller.addListener(() => _onVideoProgress(index, controller));
      if (index == _currentPage && mounted) {
        unawaited(controller.play());
        setState(() {});
      }
    } catch (_) {}
  }

  void _onVideoProgress(int index, VideoPlayerController controller) {
    if (!controller.value.isInitialized) return;
    // Video reached the end — advance to next slide
    if (controller.value.position >= controller.value.duration &&
        !controller.value.isPlaying &&
        index == _currentPage &&
        !_userInteracting &&
        widget.slides.length > 1 &&
        mounted) {
      final nextPage = (_currentPage + 1) % widget.slides.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _pauseAllVideos() {
    for (final entry in _videoControllers.entries) {
      if (entry.value.value.isInitialized) {
        entry.value.pause();
      }
    }
  }

  void _playCurrentVideo() {
    final controller = _videoControllers[_currentPage];
    if (controller != null && controller.value.isInitialized) {
      controller.play();
    }
  }

  // --- Auto-play ---

  bool _currentSlideIsPlayingVideo() {
    if (widget.slides.isEmpty) return false;
    final slide = widget.slides[_currentPage];
    if (!slide.isVideo) return false;
    final controller = _videoControllers[_currentPage];
    return controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying;
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    if (widget.slides.length <= 1) return;

    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_userInteracting && widget.slides.length > 1 && mounted) {
        // Don't advance if current slide is a video still playing
        if (_currentSlideIsPlayingVideo()) return;
        final nextPage = (_currentPage + 1) % widget.slides.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onUserTouch() {
    _userInteracting = true;
    _autoPlayTimer?.cancel();
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        _userInteracting = false;
        _startAutoPlay();
      }
    });
  }

  void _onPageChanged(int index) {
    _pauseAllVideos();
    setState(() => _currentPage = index);

    final slide = widget.slides[index];
    if (slide.isVideo) {
      if (_videoControllers.containsKey(index)) {
        _playCurrentVideo();
      } else {
        _initVideoController(index, slide);
      }
    }

    // Preload adjacent videos
    _preloadAdjacentVideos(index);
  }

  void _preloadAdjacentVideos(int index) {
    for (final i in [index - 1, index + 1]) {
      if (i >= 0 && i < widget.slides.length) {
        final slide = widget.slides[i];
        if (slide.isVideo && !_videoControllers.containsKey(i)) {
          _initVideoController(i, slide);
        }
      }
    }
    // Dispose controllers for slides more than 1 away from current
    final keep = {index, index - 1, index + 1};
    final stale = _videoControllers.keys.where((k) => !keep.contains(k) || k < 0 || k >= widget.slides.length).toList();
    for (final k in stale) {
      _videoControllers[k]?.dispose();
      _videoControllers.remove(k);
    }
  }

  // --- Navigation ---

  void _handleButtonTap(CarouselSlide slide) {
    if (widget.onButtonTap != null) {
      widget.onButtonTap!(slide);
    }
  }

  Product? _getLinkedProduct(CarouselSlide slide) {
    if (slide.buttonLinkType == 'product' && slide.buttonLinkValue != null) {
      return widget.linkedProducts[slide.buttonLinkValue];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onHorizontalDragStart: (_) => _onUserTouch(),
          child: SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.slides.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final slide = widget.slides[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildSlide(slide, index),
                );
              },
            ),
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 10),
          _buildPageIndicator(),
        ],
      ],
    );
  }

  Widget _buildSlide(CarouselSlide slide, int index) {
    final product = _getLinkedProduct(slide);
    final hasDiscount = product != null && product.isDiscountActive;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media
          _buildMedia(slide, index),

          // Gradient overlay at bottom for text readability
          if (slide.hasOverlay || slide.hasButton || hasDiscount)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),

          // Discount badge with integrated countdown (top-right)
          if (hasDiscount)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.destructive,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '-${product.discountPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (product.discountEndDate != null) ...[
                      const SizedBox(height: 2),
                      DiscountCountdown(
                        endDate: product.discountEndDate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Text overlay with translucent background
          if (slide.hasOverlay)
            Positioned(
              left: 16,
              right: slide.hasButton ? 140 : 16,
              bottom: hasDiscount ? 56 : 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (slide.title != null)
                      Text(
                        slide.title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (slide.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        slide.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Price row (for discounted products)
          if (hasDiscount)
            Positioned(
              left: 16,
              bottom: 16,
              child: Row(
                children: [
                  Text(
                    'GH\u00a2 ${product.effectivePrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'GH\u00a2 ${product.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
            ),

          // CTA Button
          if (slide.hasButton)
            Positioned(
              right: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: () => _handleButtonTap(slide),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        slide.buttonText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMedia(CarouselSlide slide, int index) {
    if (slide.isVideo) {
      final controller = _videoControllers[index];
      if (controller != null && controller.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        );
      }
      // Loading state for video — show thumbnail if available
      if (slide.thumbnailUrl != null) {
        return CachedNetworkImage(
          imageUrl: slide.thumbnailUrl!,
          fit: BoxFit.cover,
          memCacheWidth: 360,
          placeholder: (_, _) => Container(color: AppTheme.warmMist),
          errorWidget: (_, _, _) => _buildMediaPlaceholder(),
        );
      }
      return _buildMediaPlaceholder();
    }

    // Image or GIF
    return CachedNetworkImage(
      imageUrl: slide.mediaUrl,
      fit: BoxFit.cover,
      memCacheWidth: 360,
      placeholder: (_, _) => Container(color: AppTheme.warmMist),
      errorWidget: (_, _, _) => _buildMediaPlaceholder(),
    );
  }

  Widget _buildMediaPlaceholder() {
    return Container(
      color: AppTheme.warmMist,
      child: const Center(
        child: Icon(LucideIcons.image, size: 32, color: AppTheme.mutedSteel),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.slides.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isActive ? 20 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accent : AppTheme.whisperBorder,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
