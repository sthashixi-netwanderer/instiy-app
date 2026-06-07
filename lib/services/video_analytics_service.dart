import 'supabase_service.dart';

class VideoAnalyticsService {
  /// Record a video view when a user swipes to a clip
  static Future<void> recordView(String productId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    try {
      await SupabaseService.table('video_views').insert({
        'product_id': productId,
        'viewer_id': userId,
      });
    } catch (_) {
      // Silent fail — analytics should never block UX
    }
  }

  /// Record a share event with the platform used
  static Future<void> recordShare(String productId, String platform) async {
    final userId = SupabaseService.auth.currentUser?.id;
    try {
      await SupabaseService.table('video_shares').insert({
        'product_id': productId,
        'sharer_id': userId,
        'platform': platform,
      });
    } catch (_) {
      // Silent fail
    }
  }

  /// Get aggregated video analytics for all of a seller's products
  static Future<List<Map<String, dynamic>>> getSellerVideoAnalytics(String sellerId) async {
    final response = await SupabaseService.client
        .rpc('get_seller_video_analytics', params: {'p_seller_id': sellerId});
    return (response as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }
}
