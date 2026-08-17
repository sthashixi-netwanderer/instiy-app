import 'dart:isolate';
import 'supabase_service.dart';
import '../models/notification_model.dart';

class NotificationService {
  static const int _pageSize = 20;

  static Future<List<AppNotification>> getNotifications({
    int offset = 0,
    int limit = _pageSize,
    String? type,
    bool? isRead,
    String? searchQuery,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    var query = supabase
        .from('notifications')
        .select('*')
        .eq('user_id', uid);

    if (type != null && type.isNotEmpty) {
      query = query.eq('type', type);
    }

    if (isRead != null) {
      query = query.eq('is_read', isRead);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or('title.ilike.%$searchQuery%,body.ilike.%$searchQuery%');
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return Isolate.run(() => _parseNotificationsList(response));
  }

  static List<AppNotification> _parseNotificationsList(List<Map<String, dynamic>> response) {
    return response
        .map((json) => AppNotification.fromJson(json))
        .toList();
  }

  static Future<int> getUnreadCount() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return 0;

    final response = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false);

    return response.length;
  }

  static Future<void> markAsRead(String notificationId) async {
    final supabase = SupabaseService.instance;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<void> markAllAsRead() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }
}
