import '../models/referral_model.dart';
import 'supabase_service.dart';

/// Referral program data — codes are generated server-side at signup,
/// points are awarded/reversed by DB triggers when referred orders are
/// delivered/refunded. This service only reads.
class ReferralService {
  /// Validates a referral code before signup. Works pre-auth via the
  /// SECURITY DEFINER RPC (users SELECT is authenticated-only).
  static Future<bool> checkCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return false;
    try {
      return await SupabaseService.client
              .rpc('check_referral_code', params: {'p_code': cleaned})
          as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Admin-configured program rules for the "How it works" section.
  static Future<ReferralProgramConfig> getProgramConfig() async {
    try {
      final row = await SupabaseService.client
          .from('platform_settings')
          .select('value')
          .eq('key', 'referral_program')
          .maybeSingle();
      final value = row?['value'] as Map<String, dynamic>?;
      if (value != null) return ReferralProgramConfig.fromJson(value);
    } catch (_) {}
    return const ReferralProgramConfig();
  }

  /// The signed-in user's code, points and referral counts.
  static Future<ReferralSummary> getSummary() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final results = await Future.wait<dynamic>([
      SupabaseService.client
          .from('users')
          .select('referral_code, referral_points')
          .eq('id', userId)
          .single(),
      SupabaseService.client
          .from('referrals')
          .select('status')
          .eq('referrer_id', userId),
    ]);

    final user = results[0] as Map<String, dynamic>;
    final referralRows = results[1] as List<dynamic>;
    final qualified =
        referralRows.where((r) => r['status'] == 'qualified').length;

    return ReferralSummary(
      referralCode: user['referral_code'] as String? ?? '',
      points: (user['referral_points'] as num?)?.toInt() ?? 0,
      totalReferred: referralRows.length,
      qualifiedCount: qualified,
    );
  }

  /// The signed-in user's own reward for having been referred, if any.
  /// Null when nobody referred them.
  static Future<ReferredReward?> getMyReferredReward() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final row = await SupabaseService.client
        .from('referrals')
        .select('id, status, referee_points, referee_awarded_at, '
            'qualified_at, referrer:referrer_id(full_name)')
        .eq('referred_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return ReferredReward.fromJson(row);
  }

  /// Newest-first referral history with the referred user's profile.
  static Future<List<ReferralRecord>> getHistory() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final rows = await SupabaseService.client
        .from('referrals')
        .select('id, status, points_awarded, created_at, qualified_at, '
            'referred:referred_id(full_name, avatar_url)')
        .eq('referrer_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map((r) => ReferralRecord.fromJson(r)).toList();
  }
}
