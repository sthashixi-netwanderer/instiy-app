import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/product_model.dart';
import '../../models/draft_listing_model.dart';
import '../../services/draft_service.dart';
import '../../services/business_profile_service.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/app_button.dart';
import 'package:instiy/utils/formatters.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _searchQuery = '';
  String _filter = 'all';
  final Map<String, int> _viewCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.user != null) {
        ref
            .read(productProvider)
            .loadUserListings(auth.user!.id)
            .then((_) => _loadViewCounts());
        ref.read(sellerProvider).loadDashboardStats(auth.user!.id);
      }
      ref.read(productProvider).loadPublishingDraft();
    });
  }

  /// Fetches total views for the user's listings (same source as the
  /// product detail page).
  Future<void> _loadViewCounts() async {
    if (!mounted) return;
    final ids = ref
        .read(productProvider)
        .userListings
        .map((p) => p.id)
        .toList();
    if (ids.isEmpty) return;
    final counts = await ProductService.getViewCounts(ids);
    if (!mounted || counts.isEmpty) return;
    setState(() => _viewCounts.addAll(counts));
  }

  Future<void> _addProduct() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    final profile = await BusinessProfileService.getProfile(user.id);
    if (!mounted) return;

    if (profile == null) {
      _showBusinessProfileRequiredDialog();
      return;
    }

    Navigator.of(context).pushNamed('/create-listing'); // ignore: unawaited_futures
  }

  void _showBusinessProfileRequiredDialog() {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Business Profile Required'),
      description: const Text(
        'You need to set up your business profile before you can list products. '
        'This helps buyers know who they\'re buying from.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/edit-business-profile');
          },
          child: const Text('Set Up Profile'),
        ),
      ],
    );
  }

  Widget _buildPublishStatusCard(DraftListing draft, double progress) {
    final isPublishing = draft.status == DraftStatus.publishing;
    
    if (isPublishing) {
      return Container(
        margin: EdgeInsets.only(bottom: context.rh(16)),
        padding: context.rAll(16),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(color: AppTheme.whisperBorder),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.charcoalInk),
                  ),
                ),
                SizedBox(width: context.rw(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Publishing "${draft.title}"...',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.charcoalInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Please keep the app open - ${(progress * 100).toInt()}% completed',
                        style: const TextStyle(
                          color: AppTheme.mutedSteel,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(12)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.whisperBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.charcoalInk),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    } else if (draft.status == DraftStatus.failed) {
      return Container(
        margin: EdgeInsets.only(bottom: context.rh(16)),
        padding: context.rAll(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(color: const Color(0xFFFEB2B2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.alertTriangle,
                  color: Color(0xFFC53030),
                  size: 20,
                ),
                SizedBox(width: context.rw(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Failed to publish "${draft.title}"',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF9B2C2C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        draft.errorMessage ?? 'An unknown error occurred during publication.',
                        style: const TextStyle(
                          color: Color(0xFFC53030),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(12)),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: context.rw(8),
              children: [
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () async {
                    await DraftService.clearDraft();
                    ref.read(productProvider).updatePublishingDraft(null);
                  },
                  child: const Text('Dismiss'),
                ),
                ShadButton(
                  size: ShadButtonSize.sm,
                  backgroundColor: const Color(0xFFC53030),
                  hoverBackgroundColor: const Color(0xFF9B2C2C),
                  onPressed: () async {
                    await Navigator.of(context).pushNamed('/create-listing');
                    ref.read(productProvider).loadPublishingDraft(); // ignore: unawaited_futures
                  },
                  child: const Text('Fix & Republish', style: TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }


  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final prod = ref.watch(productProvider);
    final sellerP = ref.watch(sellerProvider);

    // Filter + search logic
    var userListings = prod.userListings;
    if (_filter == 'active') {
      userListings = userListings.where((p) => p.status == ProductStatus.available && p.stockQuantity > 0).toList();
    } else if (_filter == 'low_stock') {
      userListings = userListings.where((p) => p.stockQuantity > 0 && p.stockQuantity < 5).toList();
    } else if (_filter == 'out_of_stock') {
      userListings = userListings.where((p) => p.stockQuantity <= 0).toList();
    } else if (_filter == 'sold') {
      userListings = userListings.where((p) => p.status == ProductStatus.sold).toList();
    } else if (_filter == 'discounted') {
      userListings = userListings.where((p) => p.isDiscountActive).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      userListings = userListings.where((p) => p.title.toLowerCase().contains(q)).toList();
    }
    final user = auth.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('My Listings')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.package, size: 64, color: AppTheme.mutedSteel),
              const SizedBox(height: 16),
              const Text('Sign in to view your listings'),
              const SizedBox(height: 16),
              ShadButton(
                onPressed: () => Navigator.of(context).pushNamed('/login'),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      );
    }

    final stats = sellerP.dashboardStats;
    final totalCount = stats != null ? stats.totalProducts : prod.userListings.length;
    final activeCount = stats != null ? stats.activeListings : prod.userListings.where((p) => p.status == ProductStatus.available).length;
    final soldCount = stats != null ? stats.totalSold : prod.userListings.where((p) => p.status == ProductStatus.sold).length;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('My Listings')),
      body: RefreshIndicator(
        onRefresh: () async {
          final user = ref.read(authProvider).user;
          if (user != null) {
            await Future.wait([
              ref.read(productProvider).loadUserListings(user.id),
              ref.read(sellerProvider).loadDashboardStats(user.id),
            ]);
            await _loadViewCounts();
          }
          await ref.read(productProvider).loadPublishingDraft();
        },
        child: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(16), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16), context.rw(16), context.rh(16)),
        children: [
          Row(
            children: [
              _StatCard(label: 'Listings', value: '$totalCount'),
              SizedBox(width: context.rw(12)),
              _StatCard(label: 'Active', value: '$activeCount'),
              SizedBox(width: context.rw(12)),
              _StatCard(label: 'Sold', value: '$soldCount'),
            ],
          ),
          SizedBox(height: context.rh(16)),
          AppButton(
            onPressed: _addProduct,
            leading: Icon(LucideIcons.plusCircle, size: context.ri(18)),
            child: const Text('Add New Product'),
          ),
          SizedBox(height: context.rh(16)),
          // Search bar
          TextField(
            autofocus: false,
            style: TextStyle(fontSize: context.rsp(14)),
            decoration: InputDecoration(
              hintText: 'Search listings...',
              hintStyle: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
              prefixIcon: Icon(LucideIcons.search, size: context.ri(18)),
              prefixIconConstraints: BoxConstraints(minWidth: context.rw(40), minHeight: context.rh(36)),
              contentPadding: EdgeInsets.symmetric(horizontal: context.rw(12), vertical: context.rh(8)),
              filled: true,
              fillColor: AppTheme.warmMist.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rr(10)),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rr(10)),
                borderSide: BorderSide(color: AppTheme.whisperBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rr(10)),
                borderSide: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          SizedBox(height: context.rh(8)),
          // Filter chips
          SizedBox(
            height: context.rh(36),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                SizedBox(width: context.rw(8)),
                _FilterChip(label: 'Active', selected: _filter == 'active', onTap: () => setState(() => _filter = 'active')),
                SizedBox(width: context.rw(8)),
                _FilterChip(label: 'Low Stock', selected: _filter == 'low_stock', onTap: () => setState(() => _filter = 'low_stock')),
                SizedBox(width: context.rw(8)),
                _FilterChip(label: 'Out of Stock', selected: _filter == 'out_of_stock', onTap: () => setState(() => _filter = 'out_of_stock')),
                SizedBox(width: context.rw(8)),
                _FilterChip(label: 'Sold', selected: _filter == 'sold', onTap: () => setState(() => _filter = 'sold')),
                SizedBox(width: context.rw(8)),
                _FilterChip(label: 'Discounted', selected: _filter == 'discounted', onTap: () => setState(() => _filter = 'discounted')),
              ],
            ),
          ),
          SizedBox(height: context.rh(12)),
          if (prod.publishingDraft != null)
            _buildPublishStatusCard(prod.publishingDraft!, prod.publishProgress),
          if (prod.isLoading)
            const ProductGridSkeleton()
          else if (userListings.isEmpty)
            Container(
              padding: context.rAll(32),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(context.rr(16)),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: const Center(
                child: Text(
                  'No listings yet. Tap "Add New" to create one!',
                  style: TextStyle(color: AppTheme.mutedSteel),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: userListings.length,
              itemBuilder: (context, index) {
                final product = userListings[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed(
                    '/product',
                    arguments: product.id,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.pureSurface,
                      borderRadius: BorderRadius.circular(context.rr(16)),
                      border: Border.all(color: AppTheme.whisperBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              product.effectiveThumbnail != null
                                  ? CachedNetworkImage(
                                      imageUrl: product.effectiveThumbnail!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      memCacheWidth: 160,
                                      placeholder: (_, _) =>
                                          Container(color: AppTheme.warmMist),
                                      errorWidget: (_, _, _) =>
                                          Container(color: AppTheme.warmMist),
                                    )
                                  : Container(
                                      color: AppTheme.warmMist,
                                      child: const Icon(LucideIcons.image, color: AppTheme.mutedSteel),
                                    ),
                              if (product.stockQuantity <= 0)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  child: Center(
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(6)),
                                      decoration: BoxDecoration(
                                        color: AppTheme.destructive,
                                        borderRadius: BorderRadius.all(Radius.circular(context.rr(6))),
                                      ),
                                      child: Text(
                                        'Out of Stock',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: context.rsp(10),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: context.rh(8),
                                left: context.rw(8),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: context.rw(6),
                                    vertical: context.rh(3),
                                  ),
                                  decoration: BoxDecoration(
                                    color: product.stockQuantity <= 0
                                        ? AppTheme.destructive
                                        : product.stockQuantity < 5
                                            ? AppTheme.warningAmber
                                            : AppTheme.charcoalInk.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(context.rr(6)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.package,
                                        size: context.ri(10),
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: context.rw(3)),
                                      Text(
                                        product.stockQuantity <= 0
                                            ? '0 in stock'
                                            : '${product.stockQuantity} in stock',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: context.rsp(9),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (product.isDiscountActive)
                                Positioned(
                                  top: context.rh(8),
                                  right: context.rw(8),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: context.rw(6),
                                      vertical: context.rh(3),
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [Color(0xFFF43F5E), AppTheme.destructive],
                                      ),
                                      borderRadius: BorderRadius.circular(context.rr(6)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.destructive.withValues(alpha: 0.35),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.tag,
                                          size: context.ri(9),
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: context.rw(3)),
                                        Text(
                                          '-${formatCurrency(product.discountPercent)}%',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: context.rsp(9),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: context.rAll(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: context.rsp(12),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              formatGhs(product.effectivePrice),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: context.rsp(13),
                                                color: product.isDiscountActive
                                                    ? AppTheme.destructive
                                                    : AppTheme.charcoalInk,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (product.isDiscountActive) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              formatGhs(product.price),
                                              style: TextStyle(
                                                fontSize: context.rsp(9.5),
                                                color: AppTheme.mutedSteel,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ],
                                          if ((_viewCounts[product.id] ?? 0) > 0) ...[
                                            SizedBox(width: context.rw(4)),
                                            Icon(
                                              LucideIcons.eye,
                                              size: context.ri(10),
                                              color: AppTheme.mutedSteel,
                                            ),
                                            SizedBox(width: context.rw(2)),
                                            Text(
                                              '${_viewCounts[product.id]}',
                                              style: TextStyle(
                                                fontSize: context.rsp(9),
                                                color: AppTheme.mutedSteel,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (product.stockQuantity <= 0 || product.status != ProductStatus.available)
                                      Flexible(
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: context.rw(5), vertical: context.rh(2.5)),
                                          decoration: BoxDecoration(
                                            color: (product.stockQuantity <= 0 || product.status == ProductStatus.sold)
                                                ? AppTheme.destructive.withValues(alpha: 0.1)
                                                : AppTheme.warningAmber.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(context.rr(4)),
                                          ),
                                          child: Text(
                                            (product.stockQuantity <= 0 || product.status == ProductStatus.sold)
                                                ? 'Out of Stock'
                                                : product.status.displayName,
                                            style: TextStyle(
                                              fontSize: context.rsp(8),
                                              fontWeight: FontWeight.w600,
                                              color: (product.stockQuantity <= 0 || product.status == ProductStatus.sold)
                                                  ? AppTheme.destructive
                                                  : AppTheme.warningAmber,
                                            ),
                                          ),
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
                );
              },
            ),
          SizedBox(height: context.rh(80)),
        ],
      ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(16)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: context.rsp(value.length <= 3 ? 24 : value.length <= 5 ? 18 : value.length <= 7 ? 14 : 12),
                fontWeight: FontWeight.bold,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(8)),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(20)),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.whisperBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: context.rsp(13),
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.charcoalInk,
          ),
        ),
      ),
    );
  }
}
