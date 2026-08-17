import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../models/carousel_slide_model.dart';

import '../../models/product_model.dart';
import '../../providers/providers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/home_carousel.dart';
import '../../widgets/featured_carousel.dart';
import '../../widgets/product_section.dart';
import '../../widgets/category_section.dart';
import '../../widgets/user_avatar_menu.dart';
import '../auth/google_onboarding_view.dart';
import '../../widgets/responsive_layout.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialOffset = ref.read(homeProvider).scrollOffset;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use ensureInitialized — data is loaded once and cached
      ref.read(homeProvider).ensureInitialized();
      ref.read(curatedProvider).ensureInitialized();
      ref.read(carouselProvider).ensureInitialized();
    });
  }

  void _onScroll() {
    ref.read(homeProvider).saveScrollOffset(_scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
      // Guard against URL injection: only allow http(s) schemes.
      final uri = Uri.tryParse(slide.buttonLinkValue!);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication).catchError((e) {
          debugPrint('Could not launch carousel URL: $e');
          return false;
        }));
      } else {
        debugPrint('Carousel URL blocked (invalid scheme): ${slide.buttonLinkValue}');
      }
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
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const AdaptiveNav(currentIndex: 0),
      child: Stack(
        children: [
          RefreshIndicator(
            edgeOffset: context.rh(84),
            onRefresh: () async {
              await Future.wait([
                home.loadAll(),
                carouselState.refresh(),
                ref.read(curatedProvider).loadSections(),
              ]);
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: context.rh(84)),
                ),
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
          _HomeGlassHeader(
            greeting: _getGreeting(),
            businessName: home.businessName,
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
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false); // ignore: unawaited_futures
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
                onSeeAll: () => Navigator.of(context).pushNamed('/curated-collection', arguments: section.id),
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
                onSeeAll: () => Navigator.of(context).pushNamed('/curated-collection', arguments: section.id),
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

class _HomeGlassHeader extends ConsumerWidget {
  final String greeting;
  final String? businessName;
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
      top: MediaQuery.paddingOf(context).top + context.rh(8),
      left: context.rw(12),
      right: context.rw(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(20)),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(
                sigmaX: AppTheme.glassBlurHeavy, sigmaY: AppTheme.glassBlurHeavy),
            inner: const ColorFilter.matrix(AppTheme.saturateMatrix),
          ),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: context.rr(20)),
            padding: context.rPadding(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _GreetingSection(
                    greeting: greeting,
                    businessName: businessName ?? fullName?.split(' ').first ?? 'Student',
                  ),
                ),
                SizedBox(width: context.rw(12)),
                BadgeIconButton(
                  icon: LucideIcons.shoppingCart,
                  count: cart.itemCount,
                  activeColor: AppTheme.accent,
                  onPressed: onCartTap,
                ),
                BadgeIconButton(
                  icon: LucideIcons.bell,
                  count: unreadNotifs,
                  activeColor: AppTheme.accent,
                  onPressed: onNotificationTap,
                ),
                UserAvatarMenu(
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

  const _GreetingSection({
    required this.greeting,
    required this.businessName,
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

