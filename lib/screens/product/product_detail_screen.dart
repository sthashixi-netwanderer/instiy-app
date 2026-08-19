import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../widgets/skeleton.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/follow_service.dart';
import '../../services/product_service.dart';
import '../../services/business_profile_service.dart';
import '../../models/business_profile_model.dart';
import '../messages/messages_screen.dart';
import 'product_report_screen.dart';
import '../../widgets/review_section.dart';
import '../../widgets/product_card.dart';
import '../../utils/maps_helper.dart';
import '../../widgets/media_viewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/verification_badge.dart';
import '../../models/institution_model.dart';
import '../../services/institution_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product? _product;
  BusinessProfile? _businessProfile;
  List<Institution> _institutions = [];
  String? _sellerUniversity;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followerCount = 0;
  int _currentImageIndex = 0;
  Timer? _countdownTimer;
  int _discountSecondsRemaining = 0;
  List<Product> _relatedProducts = [];
  bool _isRelatedLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProduct());
  }

  Future<void> _loadProduct() async {
    final product = await ref.read(productProvider).getProduct(widget.productId);
    if (!mounted) return;
    unawaited(ref.read(productProvider).loadFavoriteIds());

    // Fetch seller's business profile and institutions
    BusinessProfile? profile;
    List<Institution> institutions = [];
    String? sellerUniversity;
    try {
      if (product != null) {
        profile = await BusinessProfileService.getProfile(product.sellerId);
        final sellerProfile = await SupabaseService.table('users')
            .select('university')
            .eq('id', product.sellerId)
            .maybeSingle();
        if (sellerProfile != null) {
          sellerUniversity = sellerProfile['university'] as String?;
        }
      }
      institutions = await InstitutionService.getInstitutions();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _product = product;
        _businessProfile = profile;
        _institutions = institutions;
        _sellerUniversity = sellerUniversity;
        _isLoading = false;
      });
      _startCountdownTimer();
      unawaited(_loadFollowStatus());
      unawaited(_loadRelatedProducts());
    }
  }

  String _getCampusShortname(String campusName) {
    if (_institutions.isEmpty) return campusName;
    final inst = _institutions.firstWhere(
      (i) => i.name.toLowerCase() == campusName.toLowerCase() || i.code.toLowerCase() == campusName.toLowerCase(),
      orElse: () => Institution(id: '', code: campusName, name: campusName),
    );
    return inst.code;
  }


  void _showInstitutionPopup(BuildContext context, String campusName) {
    final inst = _institutions.firstWhere(
      (i) => i.name.toLowerCase() == campusName.toLowerCase() || i.code.toLowerCase() == campusName.toLowerCase(),
      orElse: () => Institution(id: '', code: campusName, name: campusName),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.rr(16))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inst.logoUrl != null && inst.logoUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(context.rr(12)),
                  child: CachedNetworkImage(
                    imageUrl: inst.logoUrl!,
                    height: context.rh(80),
                    width: context.rw(80),
                    fit: BoxFit.cover,
                    memCacheWidth: 80,
                    placeholder: (context, url) => Container(
                      height: context.rh(80),
                      width: context.rw(80),
                      color: AppTheme.warmMist,
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: context.rh(80),
                      width: context.rw(80),
                      color: AppTheme.warmMist,
                      child: Icon(LucideIcons.graduationCap, size: context.ri(36), color: AppTheme.mutedSteel),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  height: context.rh(80),
                  width: context.rw(80),
                  decoration: BoxDecoration(
                    color: AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(12)),
                  ),
                  child: Icon(LucideIcons.graduationCap, size: context.ri(36), color: AppTheme.mutedSteel),
                ),
              ],
              SizedBox(height: context.rh(16)),
              Text(
                inst.code,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.rsp(20),
                  color: AppTheme.charcoalInk,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.rh(8)),
              Text(
                inst.name,
                style: TextStyle(
                  fontSize: context.rsp(14),
                  color: AppTheme.mutedSteel,
                ),
                textAlign: TextAlign.center,
              ),
              if (inst.location != null && inst.location!.isNotEmpty) ...[
                SizedBox(height: context.rh(12)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.mapPin, size: context.ri(14), color: AppTheme.mutedSteel),
                    SizedBox(width: context.rw(4)),
                    Text(
                      inst.location!,
                      style: TextStyle(
                        fontSize: context.rsp(12),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    final remaining = _product?.discountSecondsRemaining;
    if (remaining != null && remaining > 0) {
      _discountSecondsRemaining = remaining;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _discountSecondsRemaining = _product?.discountSecondsRemaining ?? 0;
          if (_discountSecondsRemaining <= 0) {
            _countdownTimer?.cancel();
          }
        });
      });
    }
  }

  String _formatCountdown(int seconds) {
    final d = Duration(seconds: seconds);
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  Future<void> _loadRelatedProducts() async {
    if (_product?.categoryId == null) return;
    setState(() => _isRelatedLoading = true);
    try {
      final related = await ProductService.getRelatedProducts(_product!.id);
      if (mounted) {
        setState(() => _relatedProducts = related);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRelatedLoading = false);
    }
  }

  Future<void> _loadFollowStatus() async {
    if (_product == null) return;
    final userId = ref.read(authProvider).user?.id;
    try {
      // Load follower count for all users
      final count = await FollowService.getFollowerCount(_product!.sellerId);
      if (mounted) setState(() => _followerCount = count);

      // Load follow status only if logged in and not own product
      if (userId != null && userId != _product!.sellerId) {
        final following = await FollowService.isFollowing(_product!.sellerId);
        if (mounted) setState(() => _isFollowing = following);
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_product == null || _isFollowLoading) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      unawaited(Navigator.of(context).pushNamed('/login'));
      return;
    }
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await FollowService.unfollow(_product!.sellerId);
        if (mounted) {
          setState(() {
            _isFollowing = false;
            if (_followerCount > 0) _followerCount--;
          });
        }
      } else {
        await FollowService.follow(_product!.sellerId);
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _requireAuth(VoidCallback callback) {
    final authProv = ref.read(authProvider);
    if (authProv.isAuthenticated) {
      callback();
    } else {
      Navigator.of(context).pushNamed('/login');
    }
  }

  Future<void> _openConversation(String userId, String sellerId, Map<String, dynamic> productRefData) async {
    await ref.read(messageProvider).createAndOpenConversation(
      buyerId: userId,
      sellerId: sellerId,
      productReference: productRefData,
    );
    if (!mounted) return;
    final conv = ref.read(messageProvider).activeConversation;
    if (conv != null) {
      unawaited(Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(conversation: conv),
        ),
      ));
    }
  }

  void _shareProduct(BuildContext context) {
    final product = _product;
    if (product == null) return;
    final text = 'Check out "${product.title}" on Instiy - GH\u00a2 ${product.price.toStringAsFixed(2)}';
    Clipboard.setData(ClipboardData(text: text));
    ShadToaster.of(context).show(
      const ShadToast(title: Text('Product link copied to clipboard!')),
    );
  }

  Future<int?> _showMarkAsSoldDialog(int currentStock) async {
    int selectedQty = 1;
    return AppTheme.showGlassDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mark as Sold',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How many units do you want to mark as sold?',
              style: const TextStyle(color: AppTheme.mutedSteel),
            ),
            const SizedBox(height: 4),
            Text(
              '$currentStock available',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.minus),
                  onPressed: selectedQty > 1
                      ? () => setDialogState(() => selectedQty--)
                      : null,
                ),
                const SizedBox(width: 16),
                Text(
                  '$selectedQty',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(width: 16),
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.plus),
                  onPressed: selectedQty < currentStock
                      ? () => setDialogState(() => selectedQty++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => setDialogState(() => selectedQty = 1),
                    child: const Text('1'),
                  ),
                ),
                const SizedBox(width: 8),
                if (currentStock >= 5)
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: () => setDialogState(() => selectedQty = 5),
                      child: const Text('5'),
                    ),
                  ),
                if (currentStock >= 5) const SizedBox(width: 8),
                Expanded(
                  child: ShadButton(
                    onPressed: () => Navigator.of(context).pop(currentStock),
                    backgroundColor: AppTheme.successMoss,
                    child: Text('All ($currentStock)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ShadButton.ghost(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ShadButton(
                    onPressed: () => Navigator.of(context).pop(selectedQty),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProv = ref.watch(authProvider);
    final productProv = ref.watch(productProvider);
    final isOwner = _product?.sellerId == authProv.user?.id;
    final isFavorited = _product != null && productProv.isFavorited(_product!.id);
    final cartProv = ref.watch(cartProvider);
    final inCart = _product != null && cartProv.isInCart(_product!.id);

    if (_isLoading) {
      return ResponsiveLayout(
        type: ResponsiveLayoutType.detail,
        backgroundColor: AppTheme.canvasWhite,
        ambientBackground: true,
        child: Column(
          children: [
            // Image skeleton
            Skeleton(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.45,
              borderRadius: BorderRadius.circular(0),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.rw(16), context.rh(16), context.rw(16), 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Seller row
                    Row(
                      children: [
                        Skeleton(width: context.ri(32), height: context.ri(32), borderRadius: BorderRadius.circular(context.rr(10))),
                        SizedBox(width: context.rw(8)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Skeleton(width: context.rw(100), height: context.rh(12)),
                            SizedBox(height: context.rh(4)),
                            Skeleton(width: context.rw(60), height: context.rh(8)),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: context.rh(16)),
                    // Title
                    Skeleton(width: double.infinity, height: context.rh(16)),
                    SizedBox(height: context.rh(8)),
                    Skeleton(width: context.rw(200), height: context.rh(16)),
                    SizedBox(height: context.rh(12)),
                    // Price
                    Skeleton(width: context.rw(80), height: context.rh(20)),
                    SizedBox(height: context.rh(20)),
                    // Tabs
                    Row(
                      children: [
                        Skeleton(width: context.rw(70), height: context.rh(28), borderRadius: BorderRadius.circular(context.rr(8))),
                        SizedBox(width: context.rw(8)),
                        Skeleton(width: context.rw(90), height: context.rh(28), borderRadius: BorderRadius.circular(context.rr(8))),
                        SizedBox(width: context.rw(8)),
                        Skeleton(width: context.rw(60), height: context.rh(28), borderRadius: BorderRadius.circular(context.rr(8))),
                      ],
                    ),
                    SizedBox(height: context.rh(16)),
                    // Content lines
                    Skeleton(width: double.infinity, height: context.rh(10)),
                    SizedBox(height: context.rh(8)),
                    Skeleton(width: double.infinity, height: context.rh(10)),
                    SizedBox(height: context.rh(8)),
                    Skeleton(width: context.rw(180), height: context.rh(10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_product == null) {
      return ResponsiveLayout(
        type: ResponsiveLayoutType.detail,
        backgroundColor: AppTheme.canvasWhite,
        ambientBackground: true,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.circleAlert, size: 48, color: AppTheme.destructive),
              const SizedBox(height: 16),
              const Text('Product not found'),
              const SizedBox(height: 16),
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: ResponsiveLayout(
        type: ResponsiveLayoutType.detail,
        backgroundColor: AppTheme.canvasWhite,
        ambientBackground: true,
        bottomNavigationBar: !isOwner && _product!.status == ProductStatus.available
            ? _buildBuyerBottomBar(authProv, cartProv, isFavorited, inCart)
            : isOwner && _product!.status == ProductStatus.available
                ? _buildOwnerBottomBar()
                : null,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: AppTheme.pureSurface,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      itemCount: _product!.imageUrls.length + (_product!.hasVideo ? 1 : 0),
                      onPageChanged: (index) {
                        setState(() => _currentImageIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final combinedMedia = [
                          if (_product!.hasVideo) ..._product!.videoUrls,
                          ..._product!.imageUrls,
                        ];

                        // First item is video if product has one
                        if (index == 0 && _product!.hasVideo) {
                          return GestureDetector(
                            onTap: () => MediaViewer.open(
                              context,
                              combinedMedia,
                              initialIndex: 0,
                            ),
                            child: _VideoPlayerTile(videoUrl: _product!.videoUrls.first),
                          );
                        }

                        final imageIndex = _product!.hasVideo ? index - 1 : index;
                        return GestureDetector(
                          onTap: () => MediaViewer.open(
                            context,
                            combinedMedia,
                            initialIndex: index,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: _product!.imageUrls[imageIndex],
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            placeholder: (_, _) => Container(color: AppTheme.warmMist),
                            errorWidget: (_, _, _) => Container(
                              color: AppTheme.warmMist,
                              child: const Icon(LucideIcons.image, size: 48, color: AppTheme.mutedSteel),
                            ),
                          ),
                        );
                      },
                    ),
                    if ((_product!.imageUrls.length + (_product!.hasVideo ? 1 : 0)) > 1)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _product!.imageUrls.length + (_product!.hasVideo ? 1 : 0),
                            (index) => Container(
                              width: _product!.hasVideo && index == 0 ? 12 : 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentImageIndex == index
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_product!.status != ProductStatus.available)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _product!.status == ProductStatus.sold
                                ? AppTheme.destructive
                                : AppTheme.warningAmber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _product!.status.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              leading: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              actions: [
                // Wishlist button
                if (!isOwner)
                  GestureDetector(
                    onTap: () => _requireAuth(() {
                      ref.read(productProvider).toggleFavorite(_product!.id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isFavorited ? AppTheme.destructive : Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.heart,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.share, color: Colors.white),
                    onPressed: () => _shareProduct(context),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (!authProv.isAuthenticated) {
                      Navigator.of(context).pushNamed('/login');
                      return;
                    }
                    Navigator.of(context).pushNamed('/cart');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(LucideIcons.shoppingCart, size: 20, color: Colors.white),
                        if (cartProv.itemCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: const BoxDecoration(
                                color: AppTheme.destructive,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                              alignment: Alignment.center,
                              child: Text(
                                '${cartProv.itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!isOwner) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _requireAuth(() {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductReportScreen(
                            productId: _product!.id,
                            productTitle: _product!.title,
                            sellerId: _product!.sellerId,
                          ),
                        ),
                      );
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.flag, size: 20, color: Colors.white),
                    ),
                  ),
                ],
                if (isOwner)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.pencil, color: Colors.white),
                      onPressed: () async {
                        final updated = await Navigator.of(context).pushNamed(
                          '/create-listing',
                          arguments: _product,
                        );
                        if (updated == true) unawaited(_loadProduct());
                      },
                    ),
                  ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: context.rAll(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _product!.title,
                      style: TextStyle(
                        fontSize: context.rsp(22),
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(height: context.rh(8)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_product!.isDiscountActive) ...[
                                Text(
                                  'GH\u00a2 ${_product!.effectivePrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: context.rsp(24),
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.destructive,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'GH\u00a2 ${_product!.price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: context.rsp(14),
                                        color: AppTheme.mutedSteel,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    SizedBox(width: context.rw(8)),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(2)),
                                      decoration: BoxDecoration(
                                        color: AppTheme.destructive,
                                        borderRadius: BorderRadius.circular(context.rr(6)),
                                      ),
                                      child: Text(
                                        '-${_product!.discountPercent.toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: context.rsp(11),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Text(
                                  'GH\u00a2 ${_product!.price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: context.rsp(24),
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Countdown timer
                    if (_product!.isDiscountActive && _discountSecondsRemaining > 0) ...[
                      SizedBox(height: context.rh(8)),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(12), vertical: context.rh(8)),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.clock, size: context.ri(14), color: AppTheme.destructive),
                            SizedBox(width: context.rw(6)),
                            Text(
                              'Expires in ${_formatCountdown(_discountSecondsRemaining)}',
                              style: TextStyle(
                                fontSize: context.rsp(13),
                                fontWeight: FontWeight.w600,
                                color: AppTheme.destructive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: context.rh(8)),
                    Wrap(
                      spacing: context.rw(8),
                      runSpacing: context.rh(8),
                      children: [
                        if (_product!.campuses.isNotEmpty)
                          ..._product!.campuses.map((c) {
                            final shortName = _getCampusShortname(c);
                            return GestureDetector(
                              onTap: () => _showInstitutionPopup(context, c),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                                decoration: BoxDecoration(
                                  color: AppTheme.successMoss.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(context.rr(8)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.mapPin,
                                      size: context.ri(13),
                                      color: AppTheme.successMoss,
                                    ),
                                    SizedBox(width: context.rw(4)),
                                    Text(
                                      shortName,
                                      style: TextStyle(
                                        color: AppTheme.successMoss,
                                        fontSize: context.rsp(12),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(context.rr(8)),
                          ),
                          child: Text(
                            _product!.condition.displayName,
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_product!.categoryName != null)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                            decoration: BoxDecoration(
                              color: AppTheme.warmMist,
                              borderRadius: BorderRadius.circular(context.rr(8)),
                            ),
                            child: Text(
                              _product!.categoryName!,
                              style: TextStyle(
                                color: AppTheme.mutedSteel,
                                fontSize: context.rsp(12),
                              ),
                            ),
                          ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                          decoration: BoxDecoration(
                            color: _product!.stockQuantity <= 0
                                ? AppTheme.destructive.withValues(alpha: 0.1)
                                : AppTheme.warningAmber.withValues(alpha: 0.1)  ,
                            borderRadius: BorderRadius.circular(context.rr(8)),
                          ),
                          child: Text(
                            _product!.stockQuantity <= 0
                                ? 'Out of Stock'
                                : '${_product!.stockQuantity} in stock',
                            style: TextStyle(
                              color: _product!.stockQuantity <= 0
                                  ? AppTheme.destructive
                                  : AppTheme.warningAmber,
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final hasDifferentFees = _product!.deliveryOption != 'pickup' &&
                                _product!.institutionDeliveryFees.isNotEmpty &&
                                _product!.institutionDeliveryFees.values.toSet().length > 1;

                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(context.rr(8)),
                              ),
                              child: Text(
                                _product!.deliveryOption == 'pickup'
                                    ? 'Pickup Only'
                                    : hasDifferentFees
                                        ? (_product!.deliveryOption == 'delivery'
                                            ? 'Delivery (Varies)'
                                            : 'Pickup & Delivery (Varies)')
                                        : _product!.deliveryOption == 'delivery'
                                            ? 'Delivery (GH¢ ${_product!.deliveryFee.toStringAsFixed(2)})'
                                            : 'Pickup & Delivery (GH¢ ${_product!.deliveryFee.toStringAsFixed(2)})',
                                style: TextStyle(
                                  color: AppTheme.charcoalInk,
                                  fontSize: context.rsp(12),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                        ),
                      ],
                    ),
                    Builder(
                      builder: (context) {
                        final hasDifferentFees = _product!.deliveryOption != 'pickup' &&
                            _product!.institutionDeliveryFees.isNotEmpty &&
                            _product!.institutionDeliveryFees.values.toSet().length > 1;

                        if (!hasDifferentFees) return const SizedBox.shrink();

                        return Padding(
                          padding: EdgeInsets.only(top: context.rh(8.0)),
                          child: Wrap(
                            spacing: context.rw(6),
                            runSpacing: context.rh(6),
                            children: _product!.institutionDeliveryFees.entries.map((entry) {
                              final shortName = _getCampusShortname(entry.key);
                              return GestureDetector(
                                onTap: () => _showInstitutionPopup(context, entry.key),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warmMist,
                                    borderRadius: BorderRadius.circular(context.rr(6)),
                                    border: Border.all(color: AppTheme.whisperBorder),
                                  ),
                                  child: Text(
                                    '$shortName: GH¢ ${entry.value.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: AppTheme.mutedSteel,
                                      fontSize: context.rsp(11),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }
                    ),
                    SizedBox(height: context.rh(16)),

                    // ── Prominent availability row ────────────────────────
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(12)),
                      decoration: BoxDecoration(
                        color: _product!.stockQuantity <= 0
                            ? AppTheme.destructive.withValues(alpha: 0.06)
                            : AppTheme.warningAmber.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(context.rr(12)),
                        border: Border.all(
                          color: _product!.stockQuantity <= 0
                              ? AppTheme.destructive.withValues(alpha: 0.25)
                              : AppTheme.warningAmber.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _product!.stockQuantity <= 0
                                ? LucideIcons.shoppingCart
                                : LucideIcons.package,
                            size: context.ri(20),
                            color: _product!.stockQuantity <= 0
                                ? AppTheme.destructive
                                : AppTheme.warningAmber,
                          ),
                          SizedBox(width: context.rw(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _product!.stockQuantity <= 0
                                      ? 'Currently Unavailable'
                                      : 'Available Quantity',
                                  style: TextStyle(
                                    fontSize: context.rsp(11),
                                    fontWeight: FontWeight.w500,
                                    color: _product!.stockQuantity <= 0
                                        ? AppTheme.destructive.withValues(alpha: 0.8)
                                        : AppTheme.warningAmber.withValues(alpha: 0.85),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                SizedBox(height: context.rh(2)),
                                Text(
                                  _product!.stockQuantity <= 0
                                      ? 'This item is out of stock'
                                      : '${_product!.stockQuantity} unit${_product!.stockQuantity == 1 ? '' : 's'} available',
                                  style: TextStyle(
                                    fontSize: context.rsp(15),
                                    fontWeight: FontWeight.w700,
                                    color: _product!.stockQuantity <= 0
                                        ? AppTheme.destructive
                                        : AppTheme.warningAmber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_product!.stockQuantity > 0 && _product!.stockQuantity <= 5)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(context.rr(6)),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Low Stock',
                                style: TextStyle(
                                  fontSize: context.rsp(11),
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: context.rh(16)),

                    // ── Seller card ──────────────────────────────────────
                    Container(
                      padding: context.rAll(16),
                      decoration: BoxDecoration(
                        color: AppTheme.warmMist,
                        borderRadius: BorderRadius.circular(context.rr(12)),
                      ),
                      child: Row(
                        children: [
                          ShadAvatar(
                            _product!.sellerAvatar?.isNotEmpty == true ? _product!.sellerAvatar : null,
                            backgroundColor: AppTheme.accent,
                            placeholder: Text(
                              (_product!.sellerName ?? 'S')[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: context.rsp(18),
                              ),
                            ),
                          ),
                          SizedBox(width: context.rw(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        // Show business name to everyone, fallback to "Unknown Seller"
                                        _businessProfile?.businessName ?? _product!.sellerName ?? 'Unknown Seller',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: context.rsp(15),
                                          color: AppTheme.charcoalInk,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_product!.isSellerVerified) ...[
                                      SizedBox(width: context.rw(6)),
                                      VerificationBadge(size: context.ri(14)),
                                    ],
                                  ],
                                ),
                                // Show full name to owner only, below business name
                                if (isOwner && _businessProfile?.businessName != null && _product!.sellerName != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: context.rh(2)),
                                    child: Text(
                                      _product!.sellerName!,
                                      style: TextStyle(
                                        fontSize: context.rsp(12),
                                        color: AppTheme.mutedSteel,
                                      ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final targetInst = (_sellerUniversity != null && _sellerUniversity!.isNotEmpty)
                                            ? _sellerUniversity
                                            : (_product!.campuses.isNotEmpty ? _product!.campuses.first : null);
                                        if (targetInst == null) return const SizedBox.shrink();

                                        final shortName = _getCampusShortname(targetInst);
                                        return Flexible(
                                          child: GestureDetector(
                                            onTap: () => _showInstitutionPopup(context, targetInst),
                                            child: Text(
                                              shortName,
                                              style: TextStyle(
                                                fontSize: context.rsp(13),
                                                color: AppTheme.mutedSteel,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final targetInst = (_sellerUniversity != null && _sellerUniversity!.isNotEmpty)
                                            ? _sellerUniversity
                                            : (_product!.campuses.isNotEmpty ? _product!.campuses.first : null);
                                        if (targetInst != null && _followerCount > 0) {
                                          return const Text(' · ', style: TextStyle(color: AppTheme.mutedSteel));
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                    if (_followerCount > 0)
                                      Text(
                                        '$_followerCount follower${_followerCount == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          fontSize: context.rsp(13),
                                          color: AppTheme.mutedSteel,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: _isFollowLoading ? null : _toggleFollow,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(3)),
                                  decoration: BoxDecoration(
                                    color: _isFollowing
                                        ? AppTheme.warmMist
                                        : AppTheme.accent,
                                    borderRadius: BorderRadius.circular(context.rr(6)),
                                    border: _isFollowing
                                        ? Border.all(color: AppTheme.whisperBorder)
                                        : null,
                                  ),
                                  child: _isFollowLoading
                                      ? SizedBox(
                                          width: context.rw(11),
                                          height: context.rh(11),
                                          child: const CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.mutedSteel),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _isFollowing ? LucideIcons.userMinus : LucideIcons.userPlus,
                                              size: context.ri(11),
                                              color: _isFollowing ? AppTheme.mutedSteel : Colors.white,
                                            ),
                                            SizedBox(width: context.rw(4)),
                                            Text(
                                              _isFollowing ? 'Unfollow' : 'Follow',
                                              style: TextStyle(
                                                fontSize: context.rsp(11),
                                                fontWeight: FontWeight.w600,
                                                color: _isFollowing ? AppTheme.mutedSteel : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: context.rh(24)),
                    SizedBox(height: context.rh(12)),
                    // Visit Store button — full width
                    SizedBox(
                      width: double.infinity,
                      child: ShadButton.outline(
                        onPressed: () => Navigator.of(context).pushNamed(
                          '/business-profile',
                          arguments: _product!.sellerId,
                        ),
                        leading: Icon(LucideIcons.store, size: context.ri(20)),
                        child: const Text('Visit Store'),
                      ),
                    ),
                    // View Store Location button
                    if (_businessProfile?.locationUrl?.isNotEmpty == true) ...[
                      SizedBox(height: context.rh(8)),
                      SizedBox(
                        width: double.infinity,
                        child: ShadButton.outline(
                          onPressed: () => _openMapPreview(_businessProfile!.locationUrl!),
                          leading: Icon(LucideIcons.mapPin, size: context.ri(20)),
                          child: const Text('View Store Location'),
                        ),
                      ),
                    ],
                    const Divider(),
                    SizedBox(height: context.rh(16)),
                    TabBar(
                      labelColor: AppTheme.accent,
                      unselectedLabelColor: AppTheme.mutedSteel,
                      indicatorColor: AppTheme.accent,
                      tabs: const [
                        Tab(text: 'Description'),
                        Tab(text: 'Specifications'),
                        Tab(text: 'Reviews'),
                      ],
                    ),
                    SizedBox(height: context.rh(16)),
                    SizedBox(
                      height: (MediaQuery.of(context).size.height * 0.6).clamp(300, 800),
                      child: TabBarView(
                        children: [
                          Text(
                            _product!.description,
                            style: TextStyle(
                              color: AppTheme.mutedSteel,
                              fontSize: context.rsp(14),
                              height: 1.5,
                            ),
                          ),
                          _SpecificationsTab(specifications: _product!.specifications),
                          ReviewSection(productId: _product!.id),
                        ],
                      ),
                    ),
                    // ── Related Products ──────────────────────────────────────
                    if (_isRelatedLoading || _relatedProducts.isNotEmpty) ...[
                      SizedBox(height: context.rh(32)),
                      Text(
                        'Related Products',
                        style: TextStyle(
                          fontSize: context.rsp(18),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                      SizedBox(height: context.rh(12)),
                      SizedBox(
                        height: context.rh(260),
                        child: _isRelatedLoading
                            ? ListView.builder(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.only(right: context.rw(16)),
                                itemCount: 4,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: EdgeInsets.only(right: index < 3 ? context.rw(12) : 0),
                                    child: SizedBox(
                                      width: context.rw(160),
                                      child: Skeleton(
                                        width: context.rw(160),
                                        height: context.rh(260),
                                        borderRadius: BorderRadius.circular(context.rr(16)),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.only(right: context.rw(16)),
                                itemCount: _relatedProducts.length,
                                separatorBuilder: (_, _) => SizedBox(width: context.rw(12)),
                                itemBuilder: (context, index) {
                                  final related = _relatedProducts[index];
                                  return SizedBox(
                                    width: context.rw(160),
                                    child: ProductCard(
                                      product: related,
                                      showSeller: true,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ProductDetailScreen(productId: related.id),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                    // Bottom padding for floating action bar
                    SizedBox(height: context.rh(100)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerBottomBar(AuthProvider authProvider, CartProvider cartProvider, bool isFavorited, bool inCart) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.rw(12), 0, context.rw(12), context.rh(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: 20),
            padding: EdgeInsets.fromLTRB(context.rw(12), context.rh(10), context.rw(12), context.rh(10)),
            child: Row(
              children: [
                // Message Seller button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!authProvider.isAuthenticated) {
                        Navigator.of(context).pushNamed('/login');
                        return;
                      }
                      final userId = authProvider.user?.id;
                      final sellerId = _product?.sellerId;
                      if (userId == null || sellerId == null) return;
                      final productRef = {
                        'product_id': _product!.id,
                        'title': _product!.title,
                        'price': _product!.price,
                        'image_url': _product!.effectiveThumbnail,
                      };
                      _openConversation(userId, sellerId, productRef);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: context.rh(12)),
                      decoration: BoxDecoration(
                        color: AppTheme.glassSurfaceLight,
                        borderRadius: BorderRadius.circular(context.rr(12)),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.send, size: context.ri(18), color: AppTheme.charcoalInk),
                          SizedBox(width: context.rw(6)),
                          Flexible(
                            child: Text(
                              'Message',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.charcoalInk,
                                fontSize: context.rsp(14),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Add to Cart button
                Expanded(
                  child: inCart
                      ? Container(
                          padding: EdgeInsets.symmetric(vertical: context.rh(12)),
                          decoration: BoxDecoration(
                            color: AppTheme.mutedSteel.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(context.rr(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.checkCircle, size: context.ri(16), color: AppTheme.mutedSteel),
                              SizedBox(width: context.rw(4)),
                              Text(
                                'In Cart',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.mutedSteel,
                                  fontSize: context.rsp(13),
                                ),
                              ),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            if (!authProvider.isAuthenticated) {
                              Navigator.of(context).pushNamed('/login');
                              return;
                            }
                            cartProvider.addToCart(
                              productId: _product!.id,
                              title: _product!.title,
                              price: _product!.effectivePrice,
                              thumbnail: _product!.effectiveThumbnail,
                              sellerId: _product!.sellerId,
                              sellerName: _product!.sellerName,
                              deliveryFee: _product!.deliveryFee,
                            );
                            ShadToaster.of(context).show(
                              ShadToast(title: Text('${_product!.title} added to cart')),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: context.rh(12)),
                            decoration: BoxDecoration(
                              color: AppTheme.glassSurfaceLight,
                              borderRadius: BorderRadius.circular(context.rr(12)),
                              border: Border.all(color: AppTheme.glassBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.shoppingCart, size: context.ri(16), color: AppTheme.charcoalInk),
                                SizedBox(width: context.rw(4)),
                                Text(
                                  'Cart',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.charcoalInk,
                                    fontSize: context.rsp(13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Buy Now button
                Expanded(
                  flex: 2,
                  child: ShadButton(
                    onPressed: () async {
                      if (!authProvider.isAuthenticated) {
                        Navigator.of(context).pushNamed('/login');
                        return;
                      }
                      if (_product != null && !_product!.isSellerVerified) {
                        final sellerName = _product!.sellerName ?? 'Unknown Seller';
                        final proceed = await AppTheme.showGlassDialog<bool>(
                          context: context,
                          title: const Text('Unverified Seller Warning'),
                          description: Text(
                            'The following seller(s) are not verified:\n'
                            '• $sellerName\n\n'
                            'Please note that Instiy will not be responsible for any misunderstanding or issues arising from transactions with unverified sellers.',
                          ),
                          actions: [
                            ShadButton.ghost(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ShadButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Proceed Anyway'),
                            ),
                          ],
                        );
                        if (proceed != true) return;
                      }
                      if (!mounted) return;
                      Navigator.of(context).pushNamed('/checkout', arguments: _product);
                    },
                    leading: const Icon(LucideIcons.shoppingBag, size: 18),
                    child: const Text('Buy Now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMapPreview(String mapsUrl) async {
    if (!MapsHelper.isGoogleMapsUrl(mapsUrl)) return;
    final uri = Uri.parse(mapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildOwnerBottomBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.rw(12), 0, context.rw(12), context.rh(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: 20),
            padding: EdgeInsets.fromLTRB(context.rw(12), context.rh(10), context.rw(12), context.rh(10)),
            child: Row(
              children: [
                // Delete button
                GestureDetector(
                  onTap: () async {
                    final provider = ref.read(productProvider);
                    final navigator = Navigator.of(context);
                    final toaster = ShadToaster.of(context);
                    final confirmed = await AppTheme.showGlassDialog<bool>(
                      context: context,
                      title: const Text('Delete Listing'),
                      description: const Text('Are you sure you want to delete this listing? This cannot be undone.'),
                      actions: [
                        ShadButton.ghost(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        ShadButton(
                          backgroundColor: AppTheme.destructive,
                          foregroundColor: Colors.white,
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    );
                    if (confirmed == true) {
                      final error = await provider.deleteProduct(_product!.id);
                      if (error != null) {
                        if (mounted) {
                          toaster.show(ShadToast(backgroundColor: AppTheme.destructive, title: Text(error)));
                        }
                      } else {
                        if (mounted) navigator.pop();
                      }
                    }
                  },
                  child: Container(
                    padding: context.rAll(10),
                    decoration: BoxDecoration(
                      color: AppTheme.destructive.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(context.rr(12)),
                      border: Border.all(color: AppTheme.destructive.withValues(alpha: 0.3)),
                    ),
                    child: Icon(LucideIcons.trash2, size: context.ri(20), color: AppTheme.destructive),
                  ),
                ),
                const SizedBox(width: 8),
                // Mark as Sold button
                Expanded(
                  child: ShadButton(
                    onPressed: () async {
                      final provider = ref.read(productProvider);
                      final stock = _product!.stockQuantity;
                      if (stock <= 1) {
                        final confirmed = await AppTheme.showGlassDialog<bool>(
                          context: context,
                          title: const Text('Mark as Sold'),
                          description: const Text('Are you sure you want to mark this item as sold?'),
                          actions: [
                            ShadButton.ghost(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ShadButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Mark as Sold'),
                            ),
                          ],
                        );
                        if (confirmed == true) {
                          await provider.updateProduct(
                            productId: _product!.id,
                            status: ProductStatus.sold,
                            stockQuantity: 0,
                          );
                          unawaited(_loadProduct());
                        }
                      } else {
                        final qty = await _showMarkAsSoldDialog(stock);
                        if (qty != null && qty > 0) {
                          final newStock = stock - qty;
                          await provider.updateProduct(
                            productId: _product!.id,
                            stockQuantity: newStock,
                            status: newStock <= 0 ? ProductStatus.sold : null,
                          );
                          unawaited(_loadProduct());
                        }
                      }
                    },
                    backgroundColor: AppTheme.successMoss,
                    foregroundColor: Colors.white,
                    leading: const Icon(LucideIcons.check, size: 18),
                    child: const Text('Mark as Sold'),
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

class _SpecificationsTab extends StatelessWidget {
  final List<Map<String, String>> specifications;

  const _SpecificationsTab({required this.specifications});

  @override
  Widget build(BuildContext context) {
    if (specifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.warmMist,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No specifications listed.',
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
        ),
      );
    }

    return Column(
      children: specifications.map((spec) {
        final key = spec.keys.first;
        final value = spec.values.first;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.whisperBorder),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.mutedSteel,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _VideoPlayerTile extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerTile({required this.videoUrl});

  @override
  State<_VideoPlayerTile> createState() => _VideoPlayerTileState();
}

class _VideoPlayerTileState extends State<_VideoPlayerTile> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initialized)
          VideoPlayer(_controller!)
        else
          Container(color: Colors.black),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _initialized ? LucideIcons.play : LucideIcons.video,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ],
    );
  }
}
