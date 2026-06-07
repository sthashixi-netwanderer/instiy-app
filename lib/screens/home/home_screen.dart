import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../models/carousel_slide_model.dart';
import '../../models/institution_model.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/supabase_service.dart';
import '../../services/institution_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/home_carousel.dart';
import '../../widgets/featured_carousel.dart';
import '../../widgets/product_section.dart';
import '../../widgets/category_section.dart';
import '../../widgets/verification_badge.dart';
import '../auth/google_onboarding_view.dart';
import '../../widgets/responsive_layout.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  List<Institution> _institutions = [];
  String? _businessName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeProvider).loadAll();
      final curated = ref.read(curatedProvider);
      curated.ensureInitialized();
      curated.loadSections();
      final carousel = ref.read(carouselProvider);
      carousel.ensureInitialized();
      carousel.loadSlides();
      _loadInstitutions();
      _loadBusinessName();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(curatedProvider).refresh();
      ref.read(carouselProvider).refresh();
    }
  }


  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutions();
      if (mounted) setState(() => _institutions = institutions);
    } catch (_) {}
  }

  Future<void> _loadBusinessName() async {
    try {
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid == null) return;
      final data = await SupabaseService.table('business_profiles')
          .select('business_name')
          .eq('seller_id', uid)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _businessName = data['business_name'] as String?);
      }
    } catch (_) {}
  }

  Institution? _findInstitution(String? universityName) {
    if (universityName == null || universityName.isEmpty || _institutions.isEmpty) return null;
    try {
      return _institutions.firstWhere(
        (i) => i.name.toLowerCase() == universityName.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  void _requireAuth(BuildContext context, VoidCallback callback) {
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      callback();
    } else {
      Navigator.of(context).pushNamed('/login');
    }
  }

  void _navigateToProduct(Product product) {
    Navigator.of(context).pushNamed('/product', arguments: product.id);
  }

  void _handleCarouselButtonTap(CarouselSlide slide) {
    if (slide.buttonLinkType == 'product' && slide.buttonLinkValue != null) {
      Navigator.of(context).pushNamed('/product', arguments: slide.buttonLinkValue);
    } else if (slide.buttonLinkType == 'category' && slide.buttonLinkValue != null) {
      Navigator.of(context).pushNamed('/explore', arguments: slide.buttonLinkValue);
    } else if (slide.buttonLinkType == 'url' && slide.buttonLinkValue != null) {
      final uri = Uri.parse(slide.buttonLinkValue!);
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated && (auth.user?.university == null ||
        auth.user!.university!.isEmpty ||
        auth.user?.phoneNumber == null ||
        auth.user!.phoneNumber!.isEmpty)) {
      return const GoogleOnboardingView();
    }

    final home = ref.watch(homeProvider);
    final carouselState = ref.watch(carouselProvider);

    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.canvasWhite,
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: context.rh(84)),
            child: RefreshIndicator(
              onRefresh: () async {
                await home.loadAll();
                await carouselState.refresh();
              },
              child: CustomScrollView(
                slivers: [
                  if (carouselState.slides.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: context.rh(16)),
                        child: HomeCarousel(
                          slides: carouselState.slides,
                          linkedProducts: carouselState.linkedProducts,
                          onButtonTap: _handleCarouselButtonTap,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: context.rh(carouselState.slides.isNotEmpty ? 16 : 20)),
                      child: home.isLoading && home.featuredProducts.isEmpty
                          ? _buildCarouselSkeleton()
                          : FeaturedCarousel(
                              products: home.featuredProducts,
                              onTap: _navigateToProduct,
                            ),
                    ),
                  ),
                  ..._buildCuratedSections(),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 120),
                  ),
                ],
              ),
            ),
          ),
          _HomeGlassHeader(
            greeting: _getGreeting(),
            businessName: _businessName,
            institution: auth.isAuthenticated ? _findInstitution(auth.user?.university) : null,
            avatarUrl: auth.user?.avatarUrl,
            fullName: auth.user?.fullName,
            isVerified: auth.user?.isVerified == true,
            isAuthenticated: auth.isAuthenticated,
            onCartTap: () => Navigator.of(context).pushNamed('/cart'),
            onNotificationTap: () => _requireAuth(context, () => Navigator.of(context).pushNamed('/notifications')),
            onLoginTap: () => Navigator.of(context).pushNamed('/login'),
            onWishlistTap: () => Navigator.of(context).pushNamed('/wishlist'),
            onOrdersTap: () => Navigator.of(context).pushNamed('/orders'),
            onWalletTap: () => Navigator.of(context).pushNamed('/wallet'),
            onFollowingTap: () => Navigator.of(context).pushNamed('/following'),
            onSettingsTap: () => Navigator.of(context).pushNamed('/account'),
            onSignOut: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCuratedSections() {
    final curated = ref.watch(curatedProvider);
    final sections = curated.sections;

    if (curated.isLoading && sections.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: context.rh(28)),
            child: _buildSectionSkeleton(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: context.rh(28)),
            child: _buildSectionSkeleton(),
          ),
        ),
      ];
    }

    if (curated.error != null && sections.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(context.rw(16), context.rh(28), context.rw(16), 0),
            child: Container(
              padding: context.rAll(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(context.rr(10)),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle, size: context.ri(16), color: Colors.red),
                  SizedBox(width: context.rw(8)),
                  Expanded(
                    child: Text(
                      curated.error!.contains('function')
                          ? 'Collections not available yet'
                          : 'Failed to load collections: ${curated.error}',
                      style: TextStyle(fontSize: context.rsp(13), color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return sections.map((section) {
      final iconData = _getIconData(section.icon);

      if (section.displayMode == 'grid') {
        // Grid display
        if (section.contentType == 'categories') {
          final categories = section.items
              .where((item) => item.category != null)
              .map((item) => item.category!)
              .toList();
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: context.rh(28)),
              child: CategoryGrid(
                title: section.title,
                subtitle: section.subtitle,
                titleIcon: iconData,
                categories: categories,
                maxItems: section.maxItems,
                onTap: (cat) => Navigator.of(context).pushNamed(
                  '/explore',
                  arguments: cat.id,
                ),
              ),
            ),
          );
        } else {
          final products = section.items
              .where((item) => item.product != null)
              .map((item) => item.product!)
              .toList();
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: context.rh(28)),
              child: ProductSection(
                title: section.title,
                titleIcon: iconData,
                products: products,
                onTap: _navigateToProduct,
                onAddToCart: (product) => ref.read(cartProvider).addToCart(
                  productId: product.id,
                  title: product.title,
                  price: product.effectivePrice,
                  thumbnail: product.effectiveThumbnail,
                  sellerId: product.sellerId,
                  sellerName: product.sellerName,
                ),
                onSeeAll: () => Navigator.of(context).pushNamed('/explore'),
              ),
            ),
          );
        }
      } else {
        // Horizontal scroll (default)
        if (section.contentType == 'categories') {
          final categories = section.items
              .where((item) => item.category != null)
              .map((item) => item.category!)
              .toList();
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: context.rh(28)),
              child: CategorySection(
                title: section.title,
                subtitle: section.subtitle,
                titleIcon: iconData,
                categories: categories,
                onTap: (cat) => Navigator.of(context).pushNamed(
                  '/explore',
                  arguments: cat.id,
                ),
              ),
            ),
          );
        } else {
          final products = section.items
              .where((item) => item.product != null)
              .map((item) => item.product!)
              .toList();
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: context.rh(28)),
              child: ProductSection(
                title: section.title,
                titleIcon: iconData,
                products: products,
                onTap: _navigateToProduct,
                onAddToCart: (product) => ref.read(cartProvider).addToCart(
                  productId: product.id,
                  title: product.title,
                  price: product.effectivePrice,
                  thumbnail: product.effectiveThumbnail,
                  sellerId: product.sellerId,
                  sellerName: product.sellerName,
                ),
                onSeeAll: () => Navigator.of(context).pushNamed('/explore'),
              ),
            ),
          );
        }
      }
    }).toList();
  }

  IconData? _getIconData(String? iconName) {
    switch (iconName) {
      case 'trending_up':
        return LucideIcons.trendingUp;
      case 'crown':
        return LucideIcons.crown;
      case 'flame':
        return LucideIcons.flame;
      case 'star':
        return LucideIcons.star;
      case 'zap':
        return LucideIcons.zap;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'new':
        return LucideIcons.badgePlus;
      case 'tag':
        return LucideIcons.tag;
      case 'grid':
        return LucideIcons.grid3x3;
      default:
        return null;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildCarouselSkeleton() {
    return Column(
      children: [
        Container(
          height: context.rh(200),
          margin: EdgeInsets.symmetric(horizontal: context.rw(16)),
          decoration: BoxDecoration(
            color: AppTheme.warmMist,
            borderRadius: BorderRadius.circular(context.rr(16)),
          ),
        ),
        SizedBox(height: context.rh(10)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (i) => Container(
              width: context.rw(i == 0 ? 20 : 6),
              height: context.rh(6),
              margin: EdgeInsets.symmetric(horizontal: context.rw(3)),
              decoration: BoxDecoration(
                color: AppTheme.whisperBorder,
                borderRadius: BorderRadius.circular(context.rr(3)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
          child: Container(
            width: context.rw(120),
            height: context.rh(20),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(context.rr(6)),
            ),
          ),
        ),
        SizedBox(height: context.rh(12)),
        SizedBox(
          height: context.rh(210),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: context.rw(12)),
            itemCount: 3,
            itemExtent: context.rw(163),
            itemBuilder: (context, index) {
              return Container(
                width: context.rw(155),
                margin: EdgeInsets.symmetric(horizontal: context.rw(4)),
                decoration: BoxDecoration(
                  color: AppTheme.warmMist,
                  borderRadius: BorderRadius.circular(context.rr(14)),
                  border: Border.all(color: AppTheme.whisperBorder),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _AvatarMenuItem {
  wishlist,
  orders,
  wallet,
  following,
  settings,
  signOut,
}

class _AvatarMenuItemRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const _AvatarMenuItemRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: destructive ? AppTheme.destructive : AppTheme.mutedSteel),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: destructive ? AppTheme.destructive : AppTheme.charcoalInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeGlassHeader extends ConsumerWidget {
  final String greeting;
  final String? businessName;
  final Institution? institution;
  final String? avatarUrl;
  final String? fullName;
  final bool isVerified;
  final bool isAuthenticated;
  final VoidCallback onCartTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onLoginTap;
  final VoidCallback onWishlistTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onWalletTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onSignOut;

  const _HomeGlassHeader({
    required this.greeting,
    this.businessName,
    this.institution,
    this.avatarUrl,
    this.fullName,
    this.isVerified = false,
    this.isAuthenticated = false,
    required this.onCartTap,
    required this.onNotificationTap,
    required this.onLoginTap,
    required this.onWishlistTap,
    required this.onOrdersTap,
    required this.onWalletTap,
    required this.onFollowingTap,
    required this.onSettingsTap,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final unreadNotifs = ref.watch(messageProvider).unreadNotificationsCount;

    return Positioned(
      top: context.rh(8),
      left: context.rw(12),
      right: context.rw(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: context.rr(20)),
            padding: context.rPadding(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _GreetingSection(
                    greeting: greeting,
                    businessName: businessName ?? fullName?.split(' ').first ?? 'Student',
                    institution: institution,
                  ),
                ),
                SizedBox(width: context.rw(12)),
                _BadgeIconButton(
                  icon: LucideIcons.shoppingCart,
                  count: cart.itemCount,
                  activeColor: AppTheme.accent,
                  onPressed: onCartTap,
                ),
                _NotificationButton(
                  unreadCount: unreadNotifs,
                  onPressed: onNotificationTap,
                ),
                _AvatarSection(
                  avatarUrl: avatarUrl,
                  fullName: fullName,
                  businessName: businessName,
                  isVerified: isVerified,
                  isAuthenticated: isAuthenticated,
                  onLoginTap: onLoginTap,
                  onWishlistTap: onWishlistTap,
                  onOrdersTap: onOrdersTap,
                  onWalletTap: onWalletTap,
                  onFollowingTap: onFollowingTap,
                  onSettingsTap: onSettingsTap,
                  onSignOut: onSignOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  final String greeting;
  final String businessName;
  final Institution? institution;

  const _GreetingSection({
    required this.greeting,
    required this.businessName,
    this.institution,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '$greeting, $businessName',
                style: TextStyle(
                  fontSize: context.rsp(18),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (institution != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: context.rPadding(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(context.rr(6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (institution!.logoUrl != null)
                      Padding(
                        padding: EdgeInsets.only(right: context.rw(4)),
                        child: CachedNetworkImage(
                          imageUrl: institution!.logoUrl!,
                          width: context.rw(14),
                          height: context.rh(14),
                          fit: BoxFit.contain,
                          memCacheWidth: 14,
                          errorWidget: (_, _, _) => Icon(LucideIcons.graduationCap, size: context.ri(12), color: AppTheme.accent),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.only(right: context.rw(4)),
                        child: Icon(LucideIcons.graduationCap, size: context.ri(12), color: AppTheme.accent),
                      ),
                    Text(
                      institution!.code,
                      style: TextStyle(
                        fontSize: context.rsp(12),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: context.rh(2)),
        Text(
          'Find what you need today',
          style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
        ),
      ],
    );
  }
}

class _BadgeIconButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color activeColor;
  final VoidCallback onPressed;

  const _BadgeIconButton({
    required this.icon,
    required this.count,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ShadIconButton.ghost(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: count > 0 ? activeColor : AppTheme.mutedSteel),
          if (count > 0)
            Positioned(
              top: context.rh(-4),
              right: context.rw(-8),
              child: Container(
                padding: context.rPadding(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.destructive,
                  borderRadius: BorderRadius.circular(context.rr(10)),
                ),
                constraints: BoxConstraints(minWidth: context.rw(16), minHeight: context.rh(16)),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: onPressed,
    );
  }
}

class _NotificationButton extends ConsumerWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _NotificationButton({
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadIconButton.ghost(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(LucideIcons.bell, color: unreadCount > 0 ? AppTheme.accent : AppTheme.mutedSteel),
          if (unreadCount > 0)
            Positioned(
              top: context.rh(-4),
              right: context.rw(-8),
              child: Container(
                padding: context.rPadding(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.destructive,
                  borderRadius: BorderRadius.circular(context.rr(10)),
                ),
                constraints: BoxConstraints(minWidth: context.rw(16), minHeight: context.rh(16)),
                alignment: Alignment.center,
                child: Text(
                  '$unreadCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: onPressed,
    );
  }
}

class _AvatarSection extends StatelessWidget {
  final String? avatarUrl;
  final String? fullName;
  final String? businessName;
  final bool isVerified;
  final bool isAuthenticated;
  final VoidCallback onLoginTap;
  final VoidCallback onWishlistTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onWalletTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onSignOut;

  const _AvatarSection({
    this.avatarUrl,
    this.fullName,
    this.businessName,
    this.isVerified = false,
    this.isAuthenticated = false,
    required this.onLoginTap,
    required this.onWishlistTap,
    required this.onOrdersTap,
    required this.onWalletTap,
    required this.onFollowingTap,
    required this.onSettingsTap,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAuthenticated) {
      return GestureDetector(
        onTap: onLoginTap,
        child: ShadAvatar(
          null,
          size: const Size(36, 36),
          backgroundColor: AppTheme.accent,
          placeholder: const Text('U', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return PopupMenuButton<_AvatarMenuItem>(
      onSelected: (item) {
        switch (item) {
          case _AvatarMenuItem.wishlist: onWishlistTap();
          case _AvatarMenuItem.orders: onOrdersTap();
          case _AvatarMenuItem.wallet: onWalletTap();
          case _AvatarMenuItem.following: onFollowingTap();
          case _AvatarMenuItem.settings: onSettingsTap();
          case _AvatarMenuItem.signOut:
            AppTheme.showGlassDialog<bool>(
              context: context,
              title: const Text('Sign Out'),
              description: const Text('Are you sure you want to sign out?'),
              actions: [
                ShadButton.ghost(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ShadButton.destructive(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Sign Out'),
                ),
              ],
            ).then((confirmed) {
              if (confirmed == true) onSignOut();
            });
        }
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.rr(12)),
        side: const BorderSide(color: AppTheme.whisperBorder),
      ),
      color: AppTheme.pureSurface,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ShadAvatar(
            avatarUrl?.isNotEmpty == true ? avatarUrl : null,
            size: const Size(36, 36),
            backgroundColor: AppTheme.accent,
            placeholder: Text(
              (businessName ?? fullName ?? 'S')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          if (isVerified)
            const Positioned(
              bottom: -2,
              right: -2,
              child: VerificationBadge(size: 14),
            ),
        ],
      ),
      itemBuilder: (context) => [
        PopupMenuItem(value: _AvatarMenuItem.wishlist, child: _AvatarMenuItemRow(icon: LucideIcons.heart, label: 'Wishlist')),
        PopupMenuItem(value: _AvatarMenuItem.orders, child: _AvatarMenuItemRow(icon: LucideIcons.shoppingBag, label: 'My Orders')),
        PopupMenuItem(value: _AvatarMenuItem.wallet, child: _AvatarMenuItemRow(icon: LucideIcons.wallet, label: 'Wallet')),
        PopupMenuItem(value: _AvatarMenuItem.following, child: _AvatarMenuItemRow(icon: LucideIcons.users, label: 'Following')),
        const PopupMenuDivider(),
        PopupMenuItem(value: _AvatarMenuItem.settings, child: _AvatarMenuItemRow(icon: LucideIcons.settings, label: 'Settings')),
        PopupMenuItem(value: _AvatarMenuItem.signOut, child: _AvatarMenuItemRow(icon: LucideIcons.logOut, label: 'Sign Out', destructive: true)),
      ],
    );
  }
}
