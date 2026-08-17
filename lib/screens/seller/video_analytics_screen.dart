import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/video_analytics_service.dart';
import '../../widgets/skeleton.dart';

class VideoAnalyticsScreen extends ConsumerStatefulWidget {
  const VideoAnalyticsScreen({super.key});

  @override
  ConsumerState<VideoAnalyticsScreen> createState() => _VideoAnalyticsScreenState();
}

class _VideoAnalyticsScreenState extends ConsumerState<VideoAnalyticsScreen> {
  List<Map<String, dynamic>> _analytics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authProvider).user;
      if (user != null) {
        final data = await VideoAnalyticsService.getSellerVideoAnalytics(user.id);
        if (mounted) {
          setState(() {
            _analytics = data;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error loading analytics: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalViews = _analytics.fold<int>(0, (sum, p) => sum + ((p['total_views'] as num?)?.toInt() ?? 0));
    final totalLikes = _analytics.fold<int>(0, (sum, p) => sum + ((p['total_likes'] as num?)?.toInt() ?? 0));
    final totalShares = _analytics.fold<int>(0, (sum, p) => sum + ((p['total_shares'] as num?)?.toInt() ?? 0));

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Video Analytics')),
      body: _isLoading
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
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  16,
                  16,
                ),
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsRow(
                    'Views',
                    '$totalViews',
                    'Likes',
                    '$totalLikes',
                    'Shares',
                    '$totalShares',
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Per Product',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_analytics.isEmpty)
                    _buildEmptyState()
                  else
                    ..._analytics.map((product) => _buildProductCard(product)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.playCircle, size: 48, color: AppTheme.mutedSteel.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'No video clips yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload a listing with a video to see analytics',
              style: TextStyle(fontSize: 13, color: AppTheme.mutedSteel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(
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

  Widget _buildProductCard(Map<String, dynamic> product) {
    final views = (product['total_views'] as num?)?.toInt() ?? 0;
    final likes = (product['total_likes'] as num?)?.toInt() ?? 0;
    final shares = (product['total_shares'] as num?)?.toInt() ?? 0;
    final engagement = views > 0 ? ((likes + shares) / views * 100).toStringAsFixed(1) : '0.0';
    final thumbnail = product['product_thumbnail'] as String?;
    final title = product['product_title'] as String? ?? 'Untitled';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: thumbnail != null && thumbnail.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: thumbnail,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    memCacheWidth: 64,
                    placeholder: (context, url) => const Skeleton(width: 64, height: 64, borderRadius: BorderRadius.all(Radius.circular(10))),
                    errorWidget: (context, url, error) => Container(
                      width: 64,
                      height: 64,
                      color: AppTheme.whisperBorder,
                      child: const Icon(LucideIcons.image, color: AppTheme.mutedSteel),
                    ),
                  )
                : Container(
                    width: 64,
                    height: 64,
                    color: AppTheme.whisperBorder,
                    child: const Icon(LucideIcons.playCircle, color: AppTheme.mutedSteel),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildMetricChip(Icons.remove_red_eye, '$views views'),
                    const SizedBox(width: 8),
                    _buildMetricChip(Icons.favorite, '$likes likes'),
                    const SizedBox(width: 8),
                    _buildMetricChip(LucideIcons.share2, '$shares shares'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$engagement% engagement',
                  style: TextStyle(
                    fontSize: 11,
                    color: double.parse(engagement) > 10
                        ? AppTheme.successMoss
                        : AppTheme.mutedSteel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppTheme.accent),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}
