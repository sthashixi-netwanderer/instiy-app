import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/product_model.dart';
import '../../services/business_profile_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.user != null) {
        ref.read(productProvider).loadUserListings(auth.user!.id);
      }
    });
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

    Navigator.of(context).pushNamed('/create-listing');
  }

  void _showBusinessProfileRequiredDialog() {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Business Profile Required'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'You need to set up your business profile before you can list products. '
            'This helps buyers know who they\'re buying from.',
            style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
          ),
          SizedBox(height: context.rh(20)),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                flex: 2,
                child: ShadButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/edit-business-profile');
                  },
                  child: const Text('Set Up Profile'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final prod = ref.watch(productProvider);
    final user = auth.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
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

    final userListings = prod.userListings;
    final activeCount = userListings.where((p) => p.status == ProductStatus.available).length;
    final soldCount = userListings.where((p) => p.status == ProductStatus.sold).length;

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('My Listings')),
      body: ListView(
        padding: context.rAll(16),
        children: [
          Row(
            children: [
              _StatCard(label: 'Listings', value: '${userListings.length}'),
              SizedBox(width: context.rw(12)),
              _StatCard(label: 'Active', value: '$activeCount'),
              SizedBox(width: context.rw(12)),
              _StatCard(label: 'Sold', value: '$soldCount'),
            ],
          ),
          SizedBox(height: context.rh(16)),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: _addProduct,
              leading: Icon(LucideIcons.plusCircle, size: context.ri(18)),
              child: const Text('Add New Product'),
            ),
          ),
          SizedBox(height: context.rh(20)),
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
                                    Text(
                                      'GH\u00a2 ${product.price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: context.rsp(13),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (product.stockQuantity <= 0 || product.status != ProductStatus.available)
                                      Container(
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
                fontSize: context.rsp(24),
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
