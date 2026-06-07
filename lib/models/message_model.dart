class Conversation {
  final String id;
  final String otherUserId;
  final String? otherUserName;
  final String? otherUserAvatar;
  final bool otherUserVerified;
  final String? otherBusinessName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isOnline;
  final bool isArchived;

  Conversation({
    required this.id,
    required this.otherUserId,
    this.otherUserName,
    this.otherUserAvatar,
    this.otherUserVerified = false,
    this.otherBusinessName,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isArchived = false,
  });

  String get displayName => otherBusinessName ?? otherUserName ?? 'Unknown';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherUserName: json['other_user_name'] as String?,
      otherUserAvatar: json['other_user_avatar'] as String?,
      otherUserVerified: json['other_user_verified'] as bool? ?? false,
      otherBusinessName: json['other_business_name'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      isOnline: json['is_online'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }
}

class ProductReference {
  final String productId;
  final String title;
  final double price;
  final String? imageUrl;

  ProductReference({
    required this.productId,
    required this.title,
    required this.price,
    this.imageUrl,
  });

  factory ProductReference.fromJson(Map<String, dynamic> json) {
    return ProductReference(
      productId: json['product_id'] as String,
      title: json['title'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'title': title,
      'price': price,
      'image_url': imageUrl,
    };
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final String? mediaType;
  final ProductReference? productReference;
  final DateTime createdAt;
  final bool isRead;
  final String status; // 'sent', 'delivered', 'seen'
  final DateTime? seenAt;
  // Reply fields
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderName;
  final String? replyToMediaUrl;
  final String? replyToMediaType;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.productReference,
    required this.createdAt,
    this.isRead = false,
    this.status = 'sent',
    this.seenAt,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderName,
    this.replyToMediaUrl,
    this.replyToMediaType,
  });

  bool get isReply => replyToMessageId != null;
  bool get isGif => mediaType == 'gif';
  bool get isSticker => mediaType == 'sticker';

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      mediaUrl: json['media_url'] as String?,
      mediaType: json['media_type'] as String?,
      productReference: json['product_reference'] != null
          ? ProductReference.fromJson(
              json['product_reference'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      status: json['status'] as String? ?? 'sent',
      seenAt: json['seen_at'] != null
          ? DateTime.parse(json['seen_at'] as String)
          : null,
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      replyToMediaUrl: json['reply_to_media_url'] as String?,
      replyToMediaType: json['reply_to_media_type'] as String?,
    );
  }
}
