import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/product_model.dart';
import '../../models/draft_listing_model.dart';
import '../../models/seller_review_model.dart';
import '../../services/business_profile_service.dart';
import '../../models/institution_model.dart';
import '../../services/institution_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/verification_badge.dart';
import 'seller_orders_screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/app_button.dart';

class SellerDashboardScreen extends ConsumerStatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  ConsumerState<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends ConsumerState<SellerDashboardScreen> {
  List<Institution> _institutions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadInstitutions();
    });
  }

  void _loadData() {
    final user = ref.read(authProvider).user;
    if (user != null) {
      ref.read(sellerProvider).ensureInitialized(user.id);
      ref.read(productProvider).loadUserListings(user.id, silent: ref.read(productProvider).userListings.isNotEmpty);
    }
    ref.read(productProvider).loadPublishingDraft();
  }

  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutions();
      if (mounted) setState(() => _institutions = institutions);
    } catch (_) {}
  }

  Future<void> _addProduct() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    final prodP = ref.read(productProvider);
    final draft = prodP.publishingDraft;
    final hasPublishingDraft = draft != null && draft.status == DraftStatus.publishing;
    if (hasPublishingDraft) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please wait for the current listing to finish publishing')),
      );
      return;
    }

    final profile = await BusinessProfileService.getProfile(user.id);
    if (!mounted) return;

    if (profile == null) {
      _showBusinessProfileRequiredDialog();
      return;
    }

    await Navigator.of(context).pushNamed(
      '/create-listing',
      arguments: {'source': 'dashboard'},
    );
    // ignore: unawaited_futures
    ref.read(productProvider).loadPublishingDraft(); // Reload draft when returning
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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
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

  Institution? _findInstitution(String? name) {
    if (name == null || name.isEmpty) return null;
    try {
      return _institutions.firstWhere(
        (i) => i.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final sellerP = ref.watch(sellerProvider);
    final prodP = ref.watch(productProvider);
    final user = auth.user;
    final stats = sellerP.dashboardStats;

    final userListings = prodP.userListings;
    final activeCount = stats != null ? stats.activeListings : userListings.where((p) => p.status == ProductStatus.available).length;
    final soldCount = stats != null ? stats.totalSold : userListings.where((p) => p.status == ProductStatus.sold).length;
    final totalStock = userListings.fold<int>(0, (sum, p) => sum + p.stockQuantity);

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Dashboard')),
      body: sellerP.isLoading && stats == null
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                16,
                16,
              ),
              child: const ListSkeleton(count: 6),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadData(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  16,
                  16,
                ),
                children: [
                  // Seller profile card
                  _buildProfileCard(user),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    children: [
                      _StatCard(label: 'Total Stocks', value: '$totalStock'),
                      const SizedBox(width: 12),
                      _StatCard(label: 'Active', value: '$activeCount', compact: true),
                      const SizedBox(width: 12),
                      _StatCard(label: 'Sold', value: '$soldCount', compact: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Edit profile + Add product
                  Row(
                    children: [
                      Expanded(
                        child: ShadButton(
                          onPressed: () => Navigator.of(context).pushNamed('/edit-profile'),
                          leading: const Icon(LucideIcons.pencil, size: 18),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Edit Profile')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ShadButton.outline(
                          onPressed: _addProduct,
                          leading: const Icon(LucideIcons.plusCircle, size: 18),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Add Product')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Build / Edit Business Profile
                  AppButton.outline(
                    onPressed: () async {
                      final result = await Navigator.of(context).pushNamed('/edit-business-profile');
                      if (result == true) _loadData();
                    },
                    leading: const Icon(LucideIcons.store, size: 18),
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Build Business Profile')),
                  ),
                  const SizedBox(height: 4),
                  // View Store link
                  Center(
                    child: ShadButton.ghost(
                      onPressed: () {
                        if (user != null) {
                          Navigator.of(context).pushNamed(
                            '/business-profile',
                            arguments: user.id,
                          );
                        }
                      },
                      size: ShadButtonSize.sm,
                      leading: const Icon(LucideIcons.externalLink, size: 13),
                      child: const Text(
                        'View Store',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Quick actions
                  _buildQuickActions(context, stats),
                  const SizedBox(height: 24),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard(dynamic user) {
    return Container(
      padding: context.rAll(20),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(20)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        children: [
          ShadAvatar(
            (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) ? user.avatarUrl : null,
            size: const Size(80, 80),
            backgroundColor: AppTheme.accent,
            placeholder: Text(
              (user?.fullName ?? 'S')[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: context.rh(12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user?.fullName ?? 'Seller',
                style: TextStyle(
                  fontSize: context.rsp(20),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              if (user?.isVerified == true) ...[
                SizedBox(width: context.rw(8)),
                const VerificationBadge(size: 18),
              ],
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: context.rh(4)),
            child: Text(
              user?.email ?? '',
              style: const TextStyle(color: AppTheme.mutedSteel),
            ),
          ),
          if (user?.university != null)
            Builder(
              builder: (context) {
                final institution = _findInstitution(user!.university);
                return Padding(
                  padding: EdgeInsets.only(top: context.rh(2)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (institution?.logoUrl != null)
                        CachedNetworkImage(
                          imageUrl: institution!.logoUrl!,
                          width: 16,
                          height: 16,
                          fit: BoxFit.contain,
                          memCacheWidth: 16,
                          placeholder: (_, _) => const Icon(LucideIcons.graduationCap, size: 14, color: AppTheme.mutedSteel),
                          errorWidget: (_, _, _) => const Icon(LucideIcons.graduationCap, size: 14, color: AppTheme.mutedSteel),
                        )
                      else
                        const Icon(LucideIcons.graduationCap, size: 14, color: AppTheme.mutedSteel),
                      SizedBox(width: context.rw(4)),
                      Text(
                        user!.university!,
                        style: const TextStyle(color: AppTheme.mutedSteel),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (user?.bio != null && user!.bio!.isNotEmpty) ...[
            SizedBox(height: context.rh(12)),
            Text(
              user.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mutedSteel, height: 1.4),
            ),
          ],
          SizedBox(height: context.rh(12)),
          // Verification badge
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/seller-profile-verification'),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: context.rw(12), vertical: context.rh(6)),
              decoration: BoxDecoration(
                color: user?.isVerified == true
                    ? AppTheme.successMoss.withValues(alpha: 0.1)
                    : AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.rr(20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  user?.isVerified == true
                      ? const VerificationBadge(size: 14)
                      : const VerificationBadge(size: 14),
                  SizedBox(width: context.rw(4)),
                  Text(
                    user?.isVerified == true ? 'Verified Seller' : 'Verify Seller',
                    style: TextStyle(
                      color: user?.isVerified == true ? AppTheme.successMoss : AppTheme.accent,
                      fontSize: context.rsp(12),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, DashboardStats? stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.package,
                  label: 'My Listings',
                  subtitle: stats != null ? '${stats.activeListings} active' : null,
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.shoppingBag,
                  label: 'Orders',
                  badge: (stats != null && stats.pendingOrders > 0) ? '${stats.pendingOrders}' : null,
                  badgeColor: AppTheme.destructive,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SellerOrdersScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.messageSquare,
                  label: 'Reviews',
                  badge: (stats != null && stats.newReviews > 0) ? '${stats.newReviews}' : null,
                  onTap: () => Navigator.of(context).pushNamed('/seller-reviews'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.wallet,
                  label: 'Wallet',
                  onTap: () => Navigator.of(context).pushNamed('/wallet'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.barChart3,
                  label: 'Analytics',
                  subtitle: stats != null ? '${stats.totalSold} sold' : null,
                  onTap: () => Navigator.of(context).pushNamed('/seller-analytics'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.playCircle,
                  label: 'Video Analytics',
                  onTap: () => Navigator.of(context).pushNamed('/seller-video-analytics'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.scanLine,
                  label: 'Verify Deliveries',
                  onTap: () => Navigator.of(context).pushNamed('/seller-verify'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.key,
                  label: 'Permissions',
                  onTap: () => Navigator.of(context).pushNamed('/seller-permissions'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;

  const _StatCard({required this.label, required this.value, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(compact ? 10 : 16)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(compact ? 10 : 14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: context.rsp(
                  compact
                      ? (value.length <= 2 ? 16 : value.length <= 4 ? 13 : 11)
                      : (value.length <= 3 ? 24 : value.length <= 5 ? 18 : value.length <= 7 ? 14 : 12),
                ),
                fontWeight: FontWeight.bold,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(compact ? 2 : 4)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(compact ? 10 : 12),
                color: AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(14), horizontal: context.rw(12)),
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
                Container(
                  padding: context.rAll(6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Icon(icon, color: AppTheme.accent, size: context.ri(18)),
                ),
                if (badge != null) ...[
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: context.rw(7), vertical: context.rh(2)),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? AppTheme.accent).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(context.rr(10)),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        fontWeight: FontWeight.w700,
                        color: badgeColor ?? AppTheme.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: context.rh(10)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: context.rsp(12),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: context.rh(1)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: context.rsp(10),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
