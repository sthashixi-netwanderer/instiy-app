import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/product_service.dart';
import '../../services/follow_service.dart';
import '../../services/video_analytics_service.dart';
import '../../services/video_service.dart';
import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';
import '../../models/seller_review_model.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/instiy_logo_placeholder.dart';
import '../../widgets/review_section.dart';
import '../../widgets/verification_badge.dart';
import '../../utils/responsive.dart';

class VideoFeedScreen extends ConsumerStatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  ConsumerState<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends ConsumerState<VideoFeedScreen> with WidgetsBindingObserver, RouteAware {
  final PageController _pageController = PageController();
  List<Product> _products = [];
  bool _isLoading = true;
  int _focusedIndex = 0;
  RealtimeChannel? _productsChannel;
  final ValueNotifier<bool> _canPlay = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVideos();
    _subscribeToProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      NavigationService.routeObserver.subscribe(this, route);
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
      _canPlay.value = true;
    }
  }

  @override
  void dispose() {
    NavigationService.routeObserver.unsubscribe(this);
    _canPlay.value = false;
    WidgetsBinding.instance.removeObserver(this);
    _canPlay.dispose();
    _productsChannel?.unsubscribe();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    try {
      final clips = await ProductService.getClipsProducts();
      if (mounted) {
        setState(() {
          _products = clips;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('Error loading clips'),
            description: Text(e.toString()),
          ),
        );
      }
    }
  }

  void _subscribeToProducts() {
    _productsChannel = Supabase.instance.client
        .channel('products-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final newProduct = payload.newRecord;
            if (newProduct['status'] != 'available') return;
            if (newProduct['stock_quantity'] == null || newProduct['stock_quantity'] <= 0) return;
            if (newProduct['video_urls'] == null ||
                (newProduct['video_urls'] as List).isEmpty) {
              return;
            }

            _loadVideos();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final deletedId = payload.oldRecord['id'] as String?;
            if (deletedId == null) return;
            setState(() {
              _products.removeWhere((p) => p.id == deletedId);
            });
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
      body: _isLoading
          ? const VideoFeedSkeleton()
          : _products.isEmpty
              ? _buildEmptyState()
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _products.length,
                  onPageChanged: (index) {
                    setState(() {
                      _focusedIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return VideoFeedItem(
                      key: ValueKey(product.id),
                      product: product,
                      isActive: index == _focusedIndex,
                      canPlay: _canPlay,
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            onPressed: _loadVideos,
            child: const Text('Refresh'),
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
      _disposeVideo();
    } else if (widget.isActive) {
      _initVideo();
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
      _controller!.play();
      setState(() {
        _isPlaying = true;
        _isMuted = false;
      });
      _controller!.setVolume(_hasAudio ? 1.0 : 0.0);
      if (!_isOwnProduct) {
        VideoAnalyticsService.recordView(widget.product.id);
      }
      return;
    }
    if (widget.product.videoUrls.isEmpty) return;

    final videoUrl = widget.product.videoUrls.first;
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

    try {
      await _controller!.initialize();
      _controller!.setLooping(true);

      // Check if video has audio track
      final hasAudio = await VideoService.checkVideoHasAudio(videoUrl);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasAudio = hasAudio;
          _isMuted = !hasAudio; // auto-mute if no audio
        });
        _controller!.setVolume(hasAudio ? 1.0 : 0.0);
        if (widget.isActive) {
          _controller!.play();
          setState(() => _isPlaying = true);
          if (!_isOwnProduct) {
            VideoAnalyticsService.recordView(widget.product.id);
          }
        }
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
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
      Navigator.of(context).pushNamed('/login');
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

  String get _shareText {
    final p = widget.product;
    return 'Check out "${p.title}" on Instiy - GH\u00a2 ${p.price.toStringAsFixed(2)}';
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share to',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildShareOption(
                      assetPath: 'assets/whatsapp-svgrepo-com.svg',
                      bgColor: const Color(0xFF25D366),
                      label: 'WhatsApp',
                      onTap: () => _shareToSocial('whatsapp'),
                    ),
                    _buildShareOption(
                      assetPath: 'assets/x.png',
                      bgColor: const Color(0xFF000000),
                      label: 'X',
                      onTap: () => _shareToSocial('twitter'),
                    ),
                    _buildShareOption(
                      assetPath: 'assets/facebook-svgrepo-com.svg',
                      bgColor: const Color(0xFF1877F2),
                      label: 'Facebook',
                      onTap: () => _shareToSocial('facebook'),
                    ),
                    _buildShareOption(
                      assetPath: 'assets/instagram-svgrepo-com.svg',
                      bgColor: const Color(0xFFE4405F),
                      label: 'Instagram',
                      onTap: () => _shareToSocial('instagram'),
                    ),
                    _buildShareOption(
                      icon: Icons.copy,
                      bgColor: AppTheme.mutedSteel,
                      label: 'Copy Link',
                      onTap: () => _shareToSocial('copy_link'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareOption({
    String? assetPath,
    IconData? icon,
    required Color bgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    Widget iconWidget;
    if (assetPath != null) {
      if (assetPath.endsWith('.svg')) {
        iconWidget = SvgPicture.asset(
          assetPath,
          width: 28,
          height: 28,
        );
      } else {
        iconWidget = Image.asset(
          assetPath,
          width: 28,
          height: 28,
        );
      }
    } else {
      iconWidget = Icon(icon, color: bgColor, size: 28);
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.charcoalInk),
          ),
        ],
      ),
    );
  }

  Future<void> _shareToSocial(String platform) async {
    final text = Uri.encodeComponent(_shareText);
    final productId = widget.product.id;
    bool launched = false;

    switch (platform) {
      case 'whatsapp':
        // Try app deep link first, fallback to web
        final appUrl = Uri.parse('whatsapp://send?text=$text');
        final webUrl = Uri.parse('https://wa.me/?text=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'twitter':
        // Try app deep link first, fallback to web intent
        final appUrl = Uri.parse('twitter://post?message=$text');
        final webUrl = Uri.parse('https://x.com/intent/post?text=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'facebook':
        // Try app deep link first, fallback to web share dialog
        final appUrl = Uri.parse('fb://sharer/sharer.php?quote=$text');
        final webUrl = Uri.parse('https://www.facebook.com/sharer/sharer.php?quote=$text');
        if (await canLaunchUrl(appUrl)) {
          launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(webUrl)) {
          launched = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }

      case 'instagram':
        // No deep link for sharing text — copy to clipboard
        await Clipboard.setData(ClipboardData(text: _shareText));
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Copied! Open Instagram and paste')),
          );
        }
        if (!_isOwnProduct) {
          VideoAnalyticsService.recordShare(productId, platform);
        }
        if (mounted) Navigator.of(context).pop();
        return;

      case 'copy_link':
        await Clipboard.setData(ClipboardData(text: _shareText));
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Link copied to clipboard!')),
          );
        }
        if (!_isOwnProduct) {
          VideoAnalyticsService.recordShare(productId, platform);
        }
        if (mounted) Navigator.of(context).pop();
        return;
    }

    // If nothing launched (app not installed, URL failed), copy to clipboard as fallback
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: _shareText));
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Copied to clipboard')),
        );
      }
    }

    if (!_isOwnProduct) {
      VideoAnalyticsService.recordShare(productId, platform);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final prodProv = ref.watch(productProvider);
    final isLiked = prodProv.isFavorited(widget.product.id);

    return Stack(
      children: [
        // Video Player Background
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlayPause,
            onDoubleTap: _handleDoubleTap,
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
                  icon: _isFollowing ? LucideIcons.userMinus : LucideIcons.userPlus,
                  color: _isFollowing ? Colors.white70 : AppTheme.accent,
                  label: _isFollowLoading
                      ? '...'
                      : _isFollowing
                          ? 'Unfollow'
                          : 'Follow',
                  onTap: _isFollowLoading ? () {} : _toggleFollow,
                ),
              ],
              if (!_isOwnProduct) ...[
                const SizedBox(height: 20),
                _buildOverlayIconButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.white,
                  label: _likeCount > 0 ? _formatCount(_likeCount) : 'Like',
                  onTap: () => prodProv.toggleFavorite(widget.product.id),
                ),
              ],
              const SizedBox(height: 20),
              _buildOverlayIconButton(
                icon: Icons.chat_bubble,
                color: Colors.white,
                label: _reviewCount > 0 ? _formatCount(_reviewCount) : 'Comments',
                onTap: _showCommentsSheet,
              ),
              const SizedBox(height: 20),
              _buildOverlayIconButton(
                icon: LucideIcons.share2,
                color: Colors.white,
                label: 'Share',
                onTap: _showShareSheet,
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
                children: [
                  Text(
                    '@${widget.product.businessName ?? widget.product.sellerName ?? 'seller'}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.rsp(16),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.product.isSellerVerified) ...[
                    const SizedBox(width: 6),
                    VerificationBadge(size: 14),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Product Info
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
                          'GH₵ ${widget.product.effectivePrice.toStringAsFixed(2)}',
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
                              '-${widget.product.discountPercent.toStringAsFixed(0)}%',
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

class VideoFeedSkeleton extends StatelessWidget {
  const VideoFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Shimmering background
        const Positioned.fill(
          child: Skeleton(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
        ),
        // Overlay outlines
        Positioned(
          right: 16,
          bottom: 120,
          child: Column(
            children: [
              const Skeleton(width: 44, height: 44, borderRadius: BorderRadius.all(Radius.circular(22))),
              const SizedBox(height: 20),
              const Skeleton(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              const SizedBox(height: 20),
              const Skeleton(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              const SizedBox(height: 20),
              const Skeleton(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              const SizedBox(height: 20),
              const Skeleton(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 80,
          bottom: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: 120, height: 16),
              const SizedBox(height: 8),
              const Skeleton(width: 200, height: 14),
              const SizedBox(height: 4),
              const Skeleton(width: double.infinity, height: 14),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Skeleton(width: 80, height: 28),
                  const SizedBox(width: 12),
                  const Skeleton(width: 100, height: 28),
                ],
              ),
            ],
          ),
        ),
      ],
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
  final _commentController = TextEditingController();
  int _rating = 5;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await ReviewService.getProductReviews(widget.productId);
      if (mounted) setState(() { _reviews = reviews; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReview() async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ReviewService.submitReview(
        productId: widget.productId,
        reviewerId: user.id,
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      _commentController.clear();
      widget.onReviewAdded();
      await _loadReviews();
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(ShadToast(title: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                    '${_reviews.length} ${_reviews.length == 1 ? 'Comment' : 'Comments'}',
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
                              'No comments yet. Be the first to comment!',
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
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 8, MediaQuery.of(context).viewInsets.bottom + 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showRatingPicker,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) => Icon(
                        i < _rating ? Icons.star : Icons.star_border,
                        color: AppTheme.warningAmber,
                        size: 20,
                      )),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitReview(),
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: AppTheme.mutedSteel),
                        filled: true,
                        fillColor: AppTheme.warmMist,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSubmitting ? null : _submitReview,
                    icon: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, color: AppTheme.accent, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showRatingPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Rate this product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => GestureDetector(
                onTap: () { setState(() => _rating = i + 1); Navigator.of(ctx).pop(); },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    size: 40,
                    color: i < _rating ? AppTheme.warningAmber : AppTheme.mutedSteel,
                  ),
                ),
              )),
            ),
            const SizedBox(height: 16),
          ],
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
                            showShadSheet(
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
              ],
            ),
          ),
        ],
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
