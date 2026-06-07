import 'supabase_service.dart';

class BlockService {
  /// Block a user — prevents them from sending messages to the blocker
  static Future<void> blockUser(String blockedId) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return;

    await SupabaseService.client.from('blocked_users').upsert({
      'blocker_id': uid,
      'blocked_id': blockedId,
    }, onConflict: 'blocker_id,blocked_id');
  }

  /// Unblock a user
  static Future<void> unblockUser(String blockedId) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return;

    await SupabaseService.client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', blockedId);
  }

  /// Check if current user has blocked a specific user
  static Future<bool> isBlocked(String userId) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return false;

    final result = await SupabaseService.client
        .from('blocked_users')
        .select('id')
        .eq('blocker_id', uid)
        .eq('blocked_id', userId)
        .maybeSingle();

    return result != null;
  }

  /// Get all blocked user IDs for the current user
  static Future<Set<String>> getBlockedUserIds() async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return {};

    final result = await SupabaseService.client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', uid);

    return (result as List)
        .map((r) => r['blocked_id'] as String)
        .toSet();
  }
}
