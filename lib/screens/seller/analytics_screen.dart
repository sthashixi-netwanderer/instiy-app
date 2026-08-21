import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/skeleton.dart';
import 'package:instiy/utils/formatters.dart';

class SellerAnalyticsScreen extends ConsumerStatefulWidget {
  const SellerAnalyticsScreen({super.key});

  @override
  ConsumerState<SellerAnalyticsScreen> createState() => _SellerAnalyticsScreenState();
}

class _SellerAnalyticsScreenState extends ConsumerState<SellerAnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref.read(sellerProvider).loadAnalytics(user.id);
        ref.read(sellerProvider).loadDashboardStats(user.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final analytics = sellerProv.analytics;
    final stats = sellerProv.dashboardStats;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Analytics')),
      body: sellerProv.isLoading && analytics == null
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
              onRefresh: () async {
                final user = ref.read(authProvider).user;
                if (user != null) {
                  await Future.wait([
                    ref.read(sellerProvider).loadAnalytics(user.id),
                    ref.read(sellerProvider).loadDashboardStats(user.id),
                  ]);
                }
              },
              child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                16,
                16,
              ),
              children: [
                const Text(
                  'Performance Overview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 16),
                if (analytics != null) ...[
                  _buildAnalyticsCard(
                    'Total Orders',
                    '${analytics['totalOrders'] ?? 0}',
                    LucideIcons.shoppingBag,
                    AppTheme.accent,
                    'All orders placed',
                  ),
                  const SizedBox(height: 12),
                  _buildAnalyticsCard(
                    'Total Earned',
                    'GH\u00a2 ${(analytics['totalEarned'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    LucideIcons.dollarSign,
                    AppTheme.successMoss,
                    'Revenue from paid orders',
                  ),
                  const SizedBox(height: 12),
                  _buildAnalyticsCard(
                    'This Month',
                    'GH\u00a2 ${(analytics['monthRevenue'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    LucideIcons.trendingUp,
                    const Color(0xFF059669),
                    'Revenue in last 30 days',
                  ),
                  const SizedBox(height: 12),
                  _buildAnalyticsCard(
                    'Avg Order Value',
                    'GH\u00a2 ${(analytics['avgOrderValue'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    LucideIcons.shoppingCart,
                    AppTheme.warningAmber,
                    'Average per order',
                  ),
                ],
                if (stats != null) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Products Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildProductStatsRow(
                    'Total Qty',
                    '${stats.totalProducts}',
                    'Active',
                    '${stats.activeListings}',
                    'Qty Sold',
                    '${stats.totalSold}',
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Reviews & Community',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAnalyticsCard(
                    'Average Rating',
                    stats.averageRating > 0 ? formatCurrency(stats.averageRating) : 'No ratings',
                    LucideIcons.star,
                    AppTheme.warningAmber,
                    '${stats.newReviews} new reviews in last 7 days',
                  ),
                  const SizedBox(height: 12),
                  _buildAnalyticsCard(
                    'Followers',
                    '${stats.followersCount}',
                    LucideIcons.users,
                    AppTheme.accent,
                    'People following your store',
                  ),
                  const SizedBox(height: 12),
                  _buildAnalyticsCard(
                    'Pending Orders',
                    '${stats.pendingOrders}',
                    LucideIcons.clock,
                    AppTheme.destructive,
                    'Orders awaiting fulfillment',
                  ),
                ],
                ],
              ),
            ),
    );
  }

  Widget _buildAnalyticsCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedSteel,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductStatsRow(
    String label1, String value1,
    String label2, String value2,
    String label3, String value3,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          Expanded(child: _buildMiniStat(label1, value1)),
          Container(width: 1, height: 40, color: AppTheme.whisperBorder),
          Expanded(child: _buildMiniStat(label2, value2)),
          Container(width: 1, height: 40, color: AppTheme.whisperBorder),
          Expanded(child: _buildMiniStat(label3, value3)),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.mutedSteel,
          ),
        ),
      ],
    );
  }
}
