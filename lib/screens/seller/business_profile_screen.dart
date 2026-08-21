import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';

import '../../config/app_theme.dart';
import '../../models/business_profile_model.dart';
import '../../models/institution_model.dart';
import '../../models/seller_review_model.dart';
import '../../providers/business_profile_provider.dart';
import '../../providers/providers.dart';
import '../../services/institution_service.dart';
import '../../services/product_service.dart';
import '../../services/review_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/share_bottom_sheet.dart';
import '../../widgets/product_card.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/review_section.dart';
import '../../widgets/app_button.dart';


class BusinessProfileScreen extends ConsumerStatefulWidget {
  final String sellerId;

  const BusinessProfileScreen({super.key, required this.sellerId});

  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reviewsScrollController = ScrollController();
  List<Institution> _institutions = [];
  final Map<String, int> _viewCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reviewsScrollController.addListener(_onReviewsScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null && route.isFirst) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
          Navigator.of(context).pushNamed('/business-profile', arguments: widget.sellerId);
          return;
        }
        ref.read(businessProfileProvider).loadStore(widget.sellerId).then((_) => _loadViewCounts());
        _loadInstitutions();
      }
    });
  }

  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutions();
      if (mounted) setState(() => _institutions = institutions);
    } catch (_) {}
  }

  /// Fetches total views for the store's products (same source as the
  /// product detail page).
  Future<void> _loadViewCounts() async {
    final ids = ref
        .read(businessProfileProvider)
        .products
        .map((p) => p.id)
        .toList();
    if (ids.isEmpty) return;
    final counts = await ProductService.getViewCounts(ids);
    if (!mounted || counts.isEmpty) return;
    setState(() => _viewCounts.addAll(counts));
  }

  Institution? _findInstitution(String? name) {
    if (name == null || _institutions.isEmpty) return null;
    try {
      return _institutions.firstWhere(
        (i) => i.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reviewsScrollController.dispose();
    super.dispose();
  }

  void _onReviewsScroll() {
    final provider = ref.read(businessProfileProvider);
    final position = _reviewsScrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.8 &&
        provider.hasMoreReviews &&
        !provider.isLoadingReviews) {
      provider.loadMoreReviews(widget.sellerId);
    }
  }

  void _requireAuth(VoidCallback callback) {
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      callback();
    } else {
      Navigator.of(context).pushNamed('/login');
    }
  }

  Future<void> _callNumber(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch tel: $e');
    }
    if (!mounted) return;
  }

  Future<void> _openWhatsApp(String number, {String? sellerName}) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
    final greeting = Uri.encodeComponent(
      'Hi${sellerName != null ? ' $sellerName' : ''}, I saw your store on Instiy and I\'m interested.',
    );
    final uri = Uri.parse('https://wa.me/$cleaned?text=$greeting');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch WhatsApp: $e');
    }
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final prov = ref.watch(businessProfileProvider);
    final currentUserId = ref.read(authProvider).user?.id;
    final isOwnProfile = currentUserId == widget.sellerId;

    if (prov.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 6),
        ),
      );
    }

    if (prov.error != null && prov.profile == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Store')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.store, size: context.ri(48), color: AppTheme.mutedSteel),
              SizedBox(height: context.rh(16)),
              const Text('Could not load store'),
              const SizedBox(height: 16),
              ShadButton(
                onPressed: () => prov.loadStore(widget.sellerId),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = prov.profile;
    final stats = prov.stats;
    final reviews = prov.reviews;
    final products = prov.products;
    final isVerified = prov.isSellerVerified;

    // Get institution from user's university (set by admin or at registration)
    final institution = _findInstitution(profile?.university);
    final firstProduct = products.isNotEmpty ? products.first : null;

    final avatarUrl = firstProduct?.sellerAvatar ?? (isOwnProfile ? ref.read(authProvider).user?.avatarUrl : null);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: RefreshIndicator(
        onRefresh: () async {
          await prov.loadStore(widget.sellerId);
          await _loadViewCounts();
        },
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // Banner
            _buildBanner(profile, isOwnProfile, avatarUrl),
            // Profile info + stats + follow + description + contact
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(profile, isOwnProfile, isVerified, institution),
                    const SizedBox(height: 16),
                    if (stats != null) _buildStatsRow(stats),
                    const SizedBox(height: 16),
                    if (!isOwnProfile) ...[
                      _buildFollowButton(prov),
                      const SizedBox(height: 16),
                    ],
                    if (profile?.description?.isNotEmpty == true) ...[
                      _buildDescription(profile!),
                      const SizedBox(height: 16),
                    ],
                    if (profile?.phoneNumbers.isNotEmpty == true) ...[
                      _buildPhoneNumbers(profile!),
                      const SizedBox(height: 16),
                    ],
                    if (profile?.locationUrl?.isNotEmpty == true) ...[
                      _buildLocation(profile!),
                    ],
                  ],
                ),
              ),
            ),
            // Tab bar
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                tabController: _tabController,
                reviewCount: reviews.length,
                productCount: products.length,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              // Products tab
              _buildProductsTab(products),
              // Reviews tab
              _buildReviewsTab(reviews, prov),
            ],
          ),
        ),
      ),
    );
  }

  // ── Banner ──────────────────────────────────────────────────────────

  Widget _buildBanner(BusinessProfile? profile, bool isOwnProfile, String? avatarUrl) {
    final hasCompleteProfile = profile != null &&
        profile.businessName != null &&
        profile.businessName!.trim().isNotEmpty;

    return SliverAppBar(
      expandedHeight: context.rh(200),
      pinned: true,
      backgroundColor: AppTheme.headerBarSolid,
      flexibleSpace: FlexibleSpaceBar(
        background: profile?.bannerUrl != null
            ? _BannerImage(bannerUrl: profile!.bannerUrl!)
            : _buildDefaultBanner(),
      ),
      leading: Container(
        margin: context.rAll(8),
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
        // Share button — visible for all profiles
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: ShadIconButton.ghost(
            icon: Icon(LucideIcons.share2, color: Colors.white, size: context.ri(18)),
            onPressed: () {
              final businessName = profile?.businessName ?? 'Seller';
              ShareBottomSheet.show(
                context,
                shareText: 'Check out "$businessName" on Instiy\n\nLink: https://instiy.com/store/${widget.sellerId}',
                analyticsId: widget.sellerId,
                analyticsType: 'store',
              );
            },
          ),
        ),
        if (isOwnProfile && hasCompleteProfile) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: ShadIconButton.ghost(
              icon: Icon(LucideIcons.qrCode, color: Colors.white, size: context.ri(18)),
              onPressed: () {
                _showQrCodeDialog(profile, avatarUrl);
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: ShadIconButton.ghost(
              icon: Icon(LucideIcons.pencil, color: Colors.white, size: context.ri(18)),
              onPressed: () async {
                final updated = await Navigator.of(context).pushNamed(
                  '/edit-business-profile',
                  arguments: profile,
                );
                if (updated == true && mounted) {
                  ref.read(businessProfileProvider).loadStore(widget.sellerId); // ignore: unawaited_futures
                }
              },
            ),
          ),
        ],
        if (!isOwnProfile && profile?.qrCodePublic == true) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: ShadIconButton.ghost(
              icon: Icon(LucideIcons.qrCode, color: Colors.white, size: context.ri(18)),
              onPressed: () {
                _showQrCodeDialog(profile, avatarUrl);
              },
            ),
          ),
        ],
      ],
    );
  }

  void _showQrCodeDialog(BusinessProfile? profile, String? avatarUrl) {
    final GlobalKey qrKey = GlobalKey();
    final sellerId = widget.sellerId;
    final businessName = profile?.businessName ?? 'Seller';
    final qrData = 'https://instiy.com/store/$sellerId';

    AppTheme.showGlassDialog(
      context: context,
      barrierDismissible: true,
      title: const Text('Store QR Code'),
      description: const Text('Scan to visit store instantly.'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: RepaintBoundary(
              key: qrKey,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.circle,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: Colors.black,
                          ),
                          embeddedImage: avatarUrl != null && avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(avatarUrl)
                              : const AssetImage('assets/logo_highres.png'),
                          embeddedImageStyle: const QrEmbeddedImageStyle(
                            size: Size(36, 36),
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => Image.asset('assets/logo_highres.png'),
                                    errorWidget: (_, _, _) => Image.asset('assets/logo_highres.png'),
                                  )
                                : Image.asset('assets/logo_highres.png'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      businessName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Scan to visit store',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedSteel,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        ShadButton(
          onPressed: () async {
            try {
              final boundary = qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              if (boundary == null) return;
              
              final image = await boundary.toImage(pixelRatio: 3.0);
              final byteData = await image.toByteData(format: ImageByteFormat.png);
              if (byteData == null) return;
              
              final bytes = byteData.buffer.asUint8List();
              if (kIsWeb) {
                // On web, save as a downloadable file instead of gallery.
                // The user can right-click the QR image to save it directly.
                if (mounted) {
                  ShadToaster.of(context).show(
                    const ShadToast(
                      title: Text('Tip'),
                      description: Text('Right-click the QR code image to save it.'),
                    ),
                  );
                }
              } else {
                await Gal.putImageBytes(bytes);
                if (mounted) {
                  ShadToaster.of(context).show(
                    const ShadToast(
                      title: Text('Saved to Gallery'),
                      description: Text('Store QR Code saved to your photo library.'),
                    ),
                  );
                }
              }
            } catch (e) {
              if (mounted) {
                ShadToaster.of(context).show(
                  ShadToast.destructive(
                    title: const Text('Failed to Save'),
                    description: Text(e.toString()),
                  ),
                );
              }
            }
          },
          child: const Text('Download'),
        ),
      ],
    );
  }

  Widget _buildDefaultBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.15),
            AppTheme.accent.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.store,
          size: context.ri(48),
          color: AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  // ── Profile Header ──────────────────────────────────────────────────

  Widget _buildProfileHeader(
    BusinessProfile? profile,
    bool isOwnProfile,
    bool isVerified,
    Institution? institution,
  ) {
    final bpProv = ref.read(businessProfileProvider);
    final firstProduct = bpProv.products.isNotEmpty ? bpProv.products.first : null;

    final businessName = profile?.businessName ??
        firstProduct?.sellerName ??
        'Seller';
    final avatarUrl = firstProduct?.sellerAvatar;

    return Row(
      children: [
        GestureDetector(
          onTap: avatarUrl?.isNotEmpty == true
              ? () => MediaViewer.open(context, [avatarUrl!], initialIndex: 0)
              : null,
          child: ShadAvatar(
            avatarUrl?.isNotEmpty == true ? avatarUrl : null,
            size: Size(context.rw(56), context.rh(56)),
            backgroundColor: AppTheme.accent,
            placeholder: Text(
              businessName[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: context.rsp(22),
                fontWeight: FontWeight.bold,
              ),
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
                      businessName,
                      style: TextStyle(
                        fontSize: context.rsp(20),
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    SizedBox(width: context.rw(6)),
                    const VerificationBadge(size: 18),
                  ],
                ],
              ),
              if (institution != null)
                Padding(
                  padding: EdgeInsets.only(top: context.rh(4)),
                  child: Row(
                    children: [
                      if (institution.logoUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: institution.logoUrl!,
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            memCacheWidth: 18,
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) =>
                                const Icon(LucideIcons.graduationCap, size: 14, color: AppTheme.mutedSteel),
                          ),
                        )
                      else
                        const Icon(LucideIcons.graduationCap, size: 14, color: AppTheme.mutedSteel),
                      SizedBox(width: context.rw(6)),
                      Flexible(
                        child: Text(
                          institution.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
                        ),
                      ),
                      SizedBox(width: context.rw(4)),
                      Text(
                        institution.code,
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Stats ───────────────────────────────────────────────────────────

  Widget _buildStatsRow(StoreStats stats) {
    return Column(
      children: [
        Row(
          children: [
            _buildStatItem('${stats.followerCount}', 'Followers'),
            Container(width: context.rw(1), height: context.rh(32), color: AppTheme.whisperBorder),
            _buildStatItem('${stats.reviewCount}', 'Reviews'),
            Container(width: context.rw(1), height: context.rh(32), color: AppTheme.whisperBorder),
            _buildStatItem(
              stats.averageRating > 0 ? stats.averageRating.toStringAsFixed(1) : '-',
              'Rating',
            ),
            Container(width: context.rw(1), height: context.rh(32), color: AppTheme.whisperBorder),
            _buildStatItem('${stats.totalProducts}', 'Products'),
          ],
        ),
        SizedBox(height: context.rh(8)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.calendar, size: context.ri(12), color: AppTheme.mutedSteel),
            SizedBox(width: context.rw(4)),
            Text(
              'Joined ${_formatJoinedDate(ref.read(businessProfileProvider).profile?.createdAt)}',
              style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
            ),
          ],
        ),
      ],
    );
  }

  String _formatJoinedDate(DateTime? date) {
    if (date == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _buildStatItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.bold,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(2)),
          Text(
            label,
            style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }

  // ── Follow Button ───────────────────────────────────────────────────

  Widget _buildFollowButton(BusinessProfileProvider provider) {
    final currentUserId = ref.watch(authProvider).user?.id;
    if (currentUserId == widget.sellerId) {
      return const SizedBox.shrink();
    }

    return provider.isFollowing
        ? AppButton.outline(
            onPressed: () => _requireAuth(() {
              provider.toggleFollow(widget.sellerId);
            }),
            leading: Icon(LucideIcons.userMinus, size: context.ri(18)),
            child: const Text('Unfollow'),
          )
        : AppButton(
            onPressed: () => _requireAuth(() {
              provider.toggleFollow(widget.sellerId);
            }),
            leading: Icon(LucideIcons.userPlus, size: context.ri(18), color: Colors.white),
            child: const Text('Follow'),
          );
  }

  // ── Description ─────────────────────────────────────────────────────

  Widget _buildDescription(BusinessProfile profile) {
    return Container(
      width: double.infinity,
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileText, size: context.ri(16), color: AppTheme.accent),
              SizedBox(width: context.rw(6)),
              Text(
                'About',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          MarkdownBody(
            data: profile.description!,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: AppTheme.charcoalInk, height: 1.5, fontSize: context.rsp(14)),
              h1: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
              h2: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
              h3: TextStyle(fontSize: context.rsp(15), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
              listBullet: const TextStyle(color: AppTheme.charcoalInk),
            ),
          ),
        ],
      ),
    );
  }

  // ── Phone Numbers ───────────────────────────────────────────────────

  Widget _buildPhoneNumbers(BusinessProfile profile) {
    final bpProv = ref.read(businessProfileProvider);
    final firstProduct = bpProv.products.isNotEmpty ? bpProv.products.first : null;
    final businessName = profile.businessName ?? firstProduct?.sellerName ?? '';

    return Container(
      width: double.infinity,
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.phone, size: context.ri(16), color: AppTheme.accent),
              SizedBox(width: context.rw(6)),
              Text(
                'Contact',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          ...profile.phoneNumbers.map((phone) => Padding(
                padding: EdgeInsets.only(bottom: context.rh(8)),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      padding: context.rAll(8),
                      decoration: BoxDecoration(
                        color: phone.isWhatsApp
                            ? const Color(0xFF25D366).withValues(alpha: 0.1)
                            : AppTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.rr(8)),
                      ),
                      child: phone.isWhatsApp
                          ? SvgPicture.asset(
                              'assets/whatsapp-svgrepo-com.svg',
                              width: 16,
                              height: 16,
                            )
                          : const Icon(LucideIcons.phone, size: 16, color: AppTheme.accent),
                    ),
                    SizedBox(width: context.rw(12)),
                    // Number + label
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phone.number,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                phone.label,
                                style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
                              ),
                              if (phone.isWhatsApp) ...[
                                SizedBox(width: context.rw(6)),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(1)),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(context.rr(4)),
                                  ),
                                  child: Text(
                                    'WhatsApp',
                                    style: TextStyle(
                                      fontSize: context.rsp(10),
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF25D366),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Call button
                    GestureDetector(
                      onTap: () => _callNumber(phone.number),
                      child: Container(
                        padding: context.rAll(8),
                        decoration: BoxDecoration(
                          color: AppTheme.successMoss.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.phone, size: context.ri(16), color: AppTheme.successMoss),
                      ),
                    ),
                    if (phone.isWhatsApp) ...[
                      SizedBox(width: context.rw(8)),
                      // WhatsApp button
                      GestureDetector(
                        onTap: () => _openWhatsApp(phone.number, sellerName: businessName),
                        child: Container(
                          padding: context.rAll(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: SvgPicture.asset(
                            'assets/whatsapp-svgrepo-com.svg',
                            width: 16,
                            height: 16,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Location ────────────────────────────────────────────────────────

  Widget _buildLocation(BusinessProfile profile) {
    return Container(
      width: double.infinity,
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.mapPin, size: context.ri(16), color: AppTheme.accent),
              SizedBox(width: context.rw(6)),
              Text(
                'Location',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => _openMapPreview(profile.locationUrl!),
                  leading: Icon(LucideIcons.map, size: context.ri(16)),
                  child: const Text('View on Map'),
                ),
              ),
              SizedBox(width: context.rw(8)),
              ShadButton.outline(
                onPressed: () => _openInGoogleMaps(profile.locationUrl!),
                leading: Icon(LucideIcons.externalLink, size: context.ri(16)),
                child: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Normalizes stored map URLs for external launch. The in-app location
  /// picker stores `output=embed` iframe links that don't open properly in
  /// browsers/Maps — convert any http(s) link carrying a `q` param (coords
  /// or address) into the universal Google Maps URL format.
  Uri _normalizedMapsUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return Uri.https('www.google.com', '/maps');
    }
    final query = uri.queryParameters['q']?.trim();
    if (query != null && query.isNotEmpty) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      });
    }
    return uri;
  }

  void _openMapPreview(String url) async {
    final uri = _normalizedMapsUri(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch map preview: $e');
    }
    if (!mounted) return;
  }

  Future<void> _openInGoogleMaps(String url) async {
    final uri = _normalizedMapsUri(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch Google Maps: $e');
    }
    if (!mounted) return;
  }

  // ── Reviews Tab ─────────────────────────────────────────────────────

  Widget _buildReviewsTab(List<ProductReview> reviews, BusinessProfileProvider provider) {
    if (reviews.isEmpty && provider.isLoadingReviews) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [ListSkeleton(count: 3)],
      );
    }

    if (reviews.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(LucideIcons.star, size: 32, color: AppTheme.mutedSteel),
                SizedBox(height: 12),
                Text(
                  'No reviews yet',
                  style: TextStyle(color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _reviewsScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: reviews.length + (provider.hasMoreReviews ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == reviews.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final userId = ref.read(authProvider).user?.id;
        return _StoreReviewCard(
          review: reviews[index],
          isOwn: reviews[index].reviewerId == userId,
          onUpdated: () => provider.reloadReviews(widget.sellerId),
        );
      },
    );
  }

  // ── Products Tab ────────────────────────────────────────────────────

  Widget _buildProductsTab(List<dynamic> products) {
    if (products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(LucideIcons.package, size: 32, color: AppTheme.mutedSteel),
                SizedBox(height: 12),
                Text(
                  'No products listed yet',
                  style: TextStyle(color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          showSeller: false,
          viewCount: _viewCounts[product.id],
          onTap: () => Navigator.of(context).pushNamed(
            '/product',
            arguments: product.id,
          ),
        );
      },
    );
  }
}

// ── Tab Bar Delegate ──────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final int reviewCount;
  final int productCount;

  _TabBarDelegate({
    required this.tabController,
    required this.reviewCount,
    required this.productCount,
  });

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.canvasWhite,
      child: TabBar(
        controller: tabController,
        labelColor: AppTheme.charcoalInk,
        unselectedLabelColor: AppTheme.mutedSteel,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        indicatorColor: AppTheme.accent,
        indicatorWeight: 2.5,
        dividerColor: AppTheme.whisperBorder,
        tabs: [
          Tab(text: 'Products ($productCount)'),
          Tab(text: 'Reviews ($reviewCount)'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return reviewCount != oldDelegate.reviewCount ||
        productCount != oldDelegate.productCount;
  }
}

// ── Store Review Card ─────────────────────────────────────────────────

class _StoreReviewCard extends StatelessWidget {
  final ProductReview review;
  final bool isOwn;
  final VoidCallback onUpdated;

  const _StoreReviewCard({
    required this.review,
    this.isOwn = false,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviewer + rating
          Row(
            children: [
              ShadAvatar(
                review.reviewerAvatar?.isNotEmpty == true ? review.reviewerAvatar : null,
                size: const Size(28, 28),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (review.reviewerName ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName ?? 'Anonymous',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    Row(
                      children: [
                        ...List.generate(5, (i) => Icon(
                          i < review.rating ? Icons.star : Icons.star_border,
                          size: 12,
                          color: i < review.rating
                              ? AppTheme.warningAmber
                              : AppTheme.mutedSteel.withValues(alpha: 0.3),
                        )),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(review.createdAt),
                          style: const TextStyle(fontSize: 10, color: AppTheme.mutedSteel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isOwn)
                PopupMenuButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.ellipsis, size: 18, color: AppTheme.mutedSteel),
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
          ),
          // Product reference
          if (review.productTitle != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (review.productThumbnail != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: review.productThumbnail!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      memCacheWidth: 32,
                      placeholder: (_, _) => Container(
                        width: 32,
                        height: 32,
                        color: AppTheme.warmMist,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 32,
                        height: 32,
                        color: AppTheme.warmMist,
                        child: const Icon(LucideIcons.image, size: 14, color: AppTheme.mutedSteel),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    review.productTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Comment
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.charcoalInk,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ],
          // Reply
          if (review.reply != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.reply, size: 12, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Seller reply',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          review.reply!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppTheme.charcoalInk, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _BannerImage extends StatelessWidget {
  final String bannerUrl;

  const _BannerImage({required this.bannerUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MediaViewer.open(context, [bannerUrl], initialIndex: 0),
      child: CachedNetworkImage(
        imageUrl: bannerUrl,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        placeholder: (_, _) => Container(color: AppTheme.warmMist),
        errorWidget: (_, _, _) => const Icon(LucideIcons.image, size: 48, color: AppTheme.mutedSteel),
      ),
    );
  }
}
