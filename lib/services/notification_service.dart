import 'dart:isolate';
import 'supabase_service.dart';
import '../models/notification_model.dart';

class NotificationService {
  static const int _pageSize = 20;

  /// Checks if a notification pertains to services.
  static bool isServiceNotification({
    String? type,
    Map<String, dynamic>? data,
    String? title,
    String? body,
  }) {
    final t = (type ?? '').toLowerCase();
    if (t.startsWith('service') || t.contains('service')) return true;
    if (data != null) {
      if (data['service_id'] != null || data['service_order_id'] != null) return true;
      final dataType = (data['type'] ?? data['kind'] ?? '').toString().toLowerCase();
      if (dataType.contains('service')) return true;
    }
    final titleLower = (title ?? '').toLowerCase();
    if (titleLower.contains('service provider') ||
        titleLower.contains('service listing') ||
        titleLower.contains('service review') ||
        titleLower.contains('your service')) {
      return true;
    }
    return false;
  }

  static Future<List<AppNotification>> getNotifications({
    int offset = 0,
    int limit = _pageSize,
    String? type,
    bool? isRead,
    String? searchQuery,
    NotificationScope scope = NotificationScope.all,
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

    final fetchMultiplier = scope == NotificationScope.all ? 1 : 4;
    final fetchLimit = limit * fetchMultiplier;
    final fetchOffset = offset * fetchMultiplier;

    final response = await query
        .order('created_at', ascending: false)
        .range(fetchOffset, fetchOffset + fetchLimit - 1);

    final allParsed = await Isolate.run(() => _parseNotificationsList(response));

    if (scope == NotificationScope.services) {
      return allParsed.where((n) => isServiceNotification(
        type: n.type,
        data: n.data,
        title: n.title,
        body: n.body,
      )).take(limit).toList();
    } else if (scope == NotificationScope.explore) {
      return allParsed.where((n) => !isServiceNotification(
        type: n.type,
        data: n.data,
        title: n.title,
        body: n.body,
      )).take(limit).toList();
    }

    return allParsed.take(limit).toList();
  }

  static List<AppNotification> _parseNotificationsList(List<Map<String, dynamic>> response) {
    return response
        .map((json) => AppNotification.fromJson(json))
        .toList();
  }

  static Future<int> getUnreadCount() async {
    final counts = await getUnreadCounts();
    return counts.total;
  }

  static Future<NotificationUnreadCounts> getUnreadCounts() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return const NotificationUnreadCounts();

    try {
      final response = await supabase
          .from('notifications')
          .select('id, type, data, title, body')
          .eq('user_id', uid)
          .eq('is_read', false);

      int serviceCount = 0;
      int exploreCount = 0;

      for (final row in response) {
        final isService = isServiceNotification(
          type: row['type'] as String?,
          data: row['data'] as Map<String, dynamic>?,
          title: row['title'] as String?,
          body: row['body'] as String?,
        );
        if (isService) {
          serviceCount++;
        } else {
          exploreCount++;
        }
      }

      return NotificationUnreadCounts(
        total: response.length,
        services: serviceCount,
        explore: exploreCount,
      );
    } catch (_) {
      return const NotificationUnreadCounts();
    }
  }

  static Future<void> markAsRead(String notificationId) async {
    final supabase = SupabaseService.instance;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<void> markAllAsRead({NotificationScope scope = NotificationScope.all}) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return;

    if (scope == NotificationScope.all) {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } else {
      final response = await supabase
          .from('notifications')
          .select('id, type, data, title, body')
          .eq('user_id', uid)
          .eq('is_read', false);

      final targetIds = <String>[];
      for (final row in response) {
        final isService = isServiceNotification(
          type: row['type'] as String?,
          data: row['data'] as Map<String, dynamic>?,
          title: row['title'] as String?,
          body: row['body'] as String?,
        );
        if (scope == NotificationScope.services && isService) {
          targetIds.add(row['id'] as String);
        } else if (scope == NotificationScope.explore && !isService) {
          targetIds.add(row['id'] as String);
        }
      }

      if (targetIds.isNotEmpty) {
        await supabase
            .from('notifications')
            .update({'is_read': true})
            .inFilter('id', targetIds);
      }
    }
  }
}

