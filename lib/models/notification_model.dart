class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String? body;
  final String? type;
  final String? referenceId;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    this.body,
    this.type,
    this.referenceId,
    this.data,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      type: json['type'] as String?,
      referenceId: json['reference_id'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

enum NotificationScope {
  all,
  services,
  explore,
}

class NotificationUnreadCounts {
  final int total;
  final int services;
  final int explore;

  const NotificationUnreadCounts({
    this.total = 0,
    this.services = 0,
    this.explore = 0,
  });
}

