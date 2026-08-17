import 'dart:isolate';
import 'supabase_service.dart';
import 'storage_service.dart';
import '../models/message_model.dart';
import 'local_db_service.dart';

class MessageService {
  static const int _pageSize = 20;

  static Future<List<Conversation>> getConversations({
    int offset = 0,
    int limit = _pageSize,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    final response = await supabase
        .from('conversations')
        .select('''
          id,
          participant1_id,
          participant2_id,
          last_message,
          last_message_at,
          theme_color,
          user1:users!conversations_participant1_id_fkey(full_name, avatar_url, is_verified, last_seen),
          user2:users!conversations_participant2_id_fkey(full_name, avatar_url, is_verified, last_seen)
        ''')
        .or('participant1_id.eq.$uid,participant2_id.eq.$uid')
        .order('last_message_at', ascending: false)
        .range(offset, offset + limit - 1);

    // Fetch archived conversation IDs for the current user
    final archivedResponse = await supabase
        .from('conversation_archives')
        .select('conversation_id')
        .eq('user_id', uid);
    final archivedIds = archivedResponse
        .map((r) => r['conversation_id'] as String)
        .toSet();

    // Fetch hidden conversations with their hidden_at timestamp
    Map<String, DateTime> hiddenMap = {};
    try {
      final hiddenResponse = await supabase
          .from('conversation_hidden')
          .select('conversation_id, hidden_at')
          .eq('user_id', uid);
      for (final r in hiddenResponse) {
        final convId = r['conversation_id'] as String?;
        final hiddenAtRaw = r['hidden_at'] as String?;
        if (convId != null && hiddenAtRaw != null) {
          hiddenMap[convId] = DateTime.parse(hiddenAtRaw);
        }
      }
    } catch (_) {
      // Table may not exist yet — treat as no hidden conversations
    }

    // Fetch unread message counts for the current user across conversations
    final unreadResponse = await supabase
        .from('messages')
        .select('conversation_id')
        .eq('receiver_id', uid)
        .eq('is_read', false);

    final Map<String, int> unreadCounts = {};
    for (final item in unreadResponse) {
      final cid = item['conversation_id'] as String?;
      if (cid != null) {
        unreadCounts[cid] = (unreadCounts[cid] ?? 0) + 1;
      }
    }

    // Fetch business profiles for conversation partners
    final otherUserIds = response.map((json) {
      final isFirst = json['participant1_id'] == uid;
      return isFirst
          ? json['participant2_id'] as String
          : json['participant1_id'] as String;
    }).toList();

    final Map<String, String> businessNames = {};
    if (otherUserIds.isNotEmpty) {
      try {
        final bizResponse = await supabase
            .from('business_profiles')
            .select('seller_id, business_name')
            .inFilter('seller_id', otherUserIds);
        for (final row in bizResponse as List) {
          final sellerId = row['seller_id'] as String?;
          final bizName = row['business_name'] as String?;
          if (sellerId != null && bizName != null && bizName.isNotEmpty) {
            businessNames[sellerId] = bizName;
          }
        }
      } catch (_) {}
    }

    final List<Conversation> result = [];
    for (final json in response) {
      final convId = json['id'] as String;
      final hiddenAt = hiddenMap[convId];
      final lastMessageAt = json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null;

      // If hidden and no new messages have arrived since deletion, skip it.
      if (hiddenAt != null &&
          (lastMessageAt == null || !lastMessageAt.isAfter(hiddenAt))) {
        continue;
      }

      final isFirst = json['participant1_id'] == uid;
      final otherProfile = isFirst
          ? json['user2'] as Map<String, dynamic>?
          : json['user1'] as Map<String, dynamic>?;
      final otherUserId = isFirst
          ? json['participant2_id'] as String
          : json['participant1_id'] as String;
      final unreadCount = unreadCounts[convId] ?? 0;

      result.add(Conversation(
        id: convId,
        otherUserId: otherUserId,
        otherUserName: otherProfile?['full_name'] as String?,
        otherUserAvatar: otherProfile?['avatar_url'] as String?,
        otherUserVerified: otherProfile?['is_verified'] as bool? ?? false,
        otherBusinessName: businessNames[otherUserId],
        lastMessage: json['last_message'] as String?,
        lastMessageAt: lastMessageAt,
        unreadCount: unreadCount,
        isArchived: archivedIds.contains(convId),
        hiddenAt: hiddenAt,
        otherUserLastSeen: otherProfile?['last_seen'] != null
            ? DateTime.parse(otherProfile!['last_seen'] as String)
            : null,
        themeColor: json['theme_color'] as String?,
      ));
    }
    return result;
  }

  static Future<Conversation?> getConversationById(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return null;

    try {
      final response = await supabase
          .from('conversations')
          .select('''
            id,
            participant1_id,
            participant2_id,
            last_message,
            last_message_at,
            theme_color,
            user1:users!conversations_participant1_id_fkey(full_name, avatar_url, is_verified, last_seen),
            user2:users!conversations_participant2_id_fkey(full_name, avatar_url, is_verified, last_seen)
          ''')
          .eq('id', conversationId)
          .maybeSingle();

      if (response == null) return null;

      // Fetch archived status
      final archivedResponse = await supabase
          .from('conversation_archives')
          .select('conversation_id')
          .eq('user_id', uid)
          .eq('conversation_id', conversationId)
          .maybeSingle();
      final isArchived = archivedResponse != null;

      // Fetch hidden status
      DateTime? hiddenAt;
      try {
        final hiddenResponse = await supabase
            .from('conversation_hidden')
            .select('hidden_at')
            .eq('user_id', uid)
            .eq('conversation_id', conversationId)
            .maybeSingle();
        if (hiddenResponse != null && hiddenResponse['hidden_at'] != null) {
          hiddenAt = DateTime.parse(hiddenResponse['hidden_at'] as String);
        }
      } catch (_) {}

      // Fetch unread count
      final unreadResponse = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .eq('receiver_id', uid)
          .eq('is_read', false);
      final unreadCount = unreadResponse.length;

      final isFirst = response['participant1_id'] == uid;
      final otherProfile = isFirst
          ? response['user2'] as Map<String, dynamic>?
          : response['user1'] as Map<String, dynamic>?;
      final otherUserId = isFirst
          ? response['participant2_id'] as String
          : response['participant1_id'] as String;

      // Fetch business profile
      String? businessName;
      try {
        final bizResponse = await supabase
            .from('business_profiles')
            .select('business_name')
            .eq('seller_id', otherUserId)
            .maybeSingle();
        if (bizResponse != null) {
          businessName = bizResponse['business_name'] as String?;
        }
      } catch (_) {}

      final lastMessageAt = response['last_message_at'] != null
          ? DateTime.parse(response['last_message_at'] as String)
          : null;

      return Conversation(
        id: conversationId,
        otherUserId: otherUserId,
        otherUserName: otherProfile?['full_name'] as String?,
        otherUserAvatar: otherProfile?['avatar_url'] as String?,
        otherUserVerified: otherProfile?['is_verified'] as bool? ?? false,
        otherBusinessName: businessName,
        lastMessage: response['last_message'] as String?,
        lastMessageAt: lastMessageAt,
        unreadCount: unreadCount,
        isArchived: isArchived,
        hiddenAt: hiddenAt,
        otherUserLastSeen: otherProfile?['last_seen'] != null
            ? DateTime.parse(otherProfile!['last_seen'] as String)
            : null,
        themeColor: response['theme_color'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get archived conversations for the current user
  static Future<List<Conversation>> getArchivedConversations({
    int offset = 0,
    int limit = _pageSize,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    // Fetch archived conversation IDs
    final archivedResponse = await supabase
        .from('conversation_archives')
        .select('conversation_id')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    if (archivedResponse.isEmpty) return [];

    final archivedConvIds = archivedResponse
        .map((r) => r['conversation_id'] as String)
        .toList();

    // Fetch the actual conversations
    final response = await supabase
        .from('conversations')
        .select('''
          id,
          participant1_id,
          participant2_id,
          last_message,
          last_message_at,
          theme_color,
          user1:users!conversations_participant1_id_fkey(full_name, avatar_url, is_verified, last_seen),
          user2:users!conversations_participant2_id_fkey(full_name, avatar_url, is_verified, last_seen)
        ''')
        .inFilter('id', archivedConvIds)
        .order('last_message_at', ascending: false);

    // Fetch unread counts
    final unreadResponse = await supabase
        .from('messages')
        .select('conversation_id')
        .eq('receiver_id', uid)
        .eq('is_read', false);
    final Map<String, int> unreadCounts = {};
    for (final item in unreadResponse) {
      final cid = item['conversation_id'] as String?;
      if (cid != null) {
        unreadCounts[cid] = (unreadCounts[cid] ?? 0) + 1;
      }
    }

    // Fetch business profiles
    final otherUserIds = response.map((json) {
      final isFirst = json['participant1_id'] == uid;
      return isFirst
          ? json['participant2_id'] as String
          : json['participant1_id'] as String;
    }).toList();

    final Map<String, String> businessNames = {};
    if (otherUserIds.isNotEmpty) {
      try {
        final bizResponse = await supabase
            .from('business_profiles')
            .select('seller_id, business_name')
            .inFilter('seller_id', otherUserIds);
        for (final row in bizResponse as List) {
          final sellerId = row['seller_id'] as String?;
          final bizName = row['business_name'] as String?;
          if (sellerId != null && bizName != null && bizName.isNotEmpty) {
            businessNames[sellerId] = bizName;
          }
        }
      } catch (_) {}
    }

    return response.map((json) {
      final isFirst = json['participant1_id'] == uid;
      final otherProfile = isFirst
          ? json['user2'] as Map<String, dynamic>?
          : json['user1'] as Map<String, dynamic>?;
      final otherUserId = isFirst
          ? json['participant2_id'] as String
          : json['participant1_id'] as String;
      final convId = json['id'] as String;

      return Conversation(
        id: convId,
        otherUserId: otherUserId,
        otherUserName: otherProfile?['full_name'] as String?,
        otherUserAvatar: otherProfile?['avatar_url'] as String?,
        otherUserVerified: otherProfile?['is_verified'] as bool? ?? false,
        otherBusinessName: businessNames[otherUserId],
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String)
            : null,
        unreadCount: unreadCounts[convId] ?? 0,
        isArchived: true,
        themeColor: json['theme_color'] as String?,
      );
    }).toList();
  }

  /// Hide (soft-delete) a conversation for the current user only.
  /// Stores hidden_at so messages before this timestamp stay hidden even
  /// if the conversation resurfaces when the other user sends a new message.
  static Future<DateTime> hideConversation(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return DateTime.now();

    final hiddenAt = DateTime.now().toUtc();
    await supabase.from('conversation_hidden').upsert({
      'user_id': uid,
      'conversation_id': conversationId,
      'hidden_at': hiddenAt.toIso8601String(),
    });
    return hiddenAt;
  }

  /// Archive a conversation for the current user
  static Future<void> archiveConversation(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return;

    await supabase.from('conversation_archives').upsert({
      'user_id': uid,
      'conversation_id': conversationId,
    });
  }

  /// Unarchive a conversation for the current user
  static Future<void> unarchiveConversation(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return;

    await supabase
        .from('conversation_archives')
        .delete()
        .eq('user_id', uid)
        .eq('conversation_id', conversationId);
  }

  /// Get messages for a conversation, newest first (for reverse pagination).
  /// [hiddenAt] — if set, only messages created after this timestamp are returned,
  /// implementing WhatsApp-style "delete chat" where old history stays hidden.
  static Future<List<Message>> getMessages(
    String conversationId, {
    int offset = 0,
    int limit = _pageSize,
    DateTime? hiddenAt,
  }) async {
    final supabase = SupabaseService.instance;

    try {
      var query = supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId);

      // Only show messages sent after the user deleted the chat
      if (hiddenAt != null) {
        query = query.gt('created_at', hiddenAt.toIso8601String());
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 5));

      // Cache the raw JSON data offline
      await LocalDbService.instance.cacheMessages(response);

      // Await inside the try so an isolate parse failure falls back to the
      // SQLite cache instead of propagating to the caller.
      return await Isolate.run(() => _parseMessagesList(response));
    } catch (e) {
      // Fallback to SQLite cache if offline or slow network
      final cached = await LocalDbService.instance.getCachedMessages(
        conversationId,
        limit: limit,
        offset: offset,
      );
      // Apply hiddenAt filter to cached results too
      final filtered = hiddenAt != null
          ? cached.where((m) => m.createdAt.isAfter(hiddenAt)).toList()
          : cached;
      return filtered.reversed.toList();
    }
  }

  static List<Message> _parseMessagesList(List<Map<String, dynamic>> response) {
    return response
        .map((json) => Message.fromJson(json))
        .toList()
        .reversed
        .toList();
  }

  static Future<Message> sendMessage({
    required String conversationId,
    required String content,
    Map<String, dynamic>? productReference,
    String? replyToMessageId,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': uid,
      'content': content,
    };
    if (productReference != null) {
      payload['product_reference'] = productReference;
    }
    if (replyToMessageId != null) {
      payload['reply_to_message_id'] = replyToMessageId;
    }

    final row = await supabase.from('messages').insert(payload).select().single();
    final message = Message.fromJson(row);

    // Build a meaningful last_message snippet
    String lastSnippet = content;
    if (lastSnippet.isEmpty && productReference != null) {
      final title = productReference['title'] as String? ?? 'Product';
      lastSnippet = '\u{1F4F7} Shared: $title';
    }
    if (replyToMessageId != null && lastSnippet.isNotEmpty) {
      lastSnippet = '\u{21A9}\uFE0F $lastSnippet';
    }

    await supabase.from('conversations').update({
      'last_message': lastSnippet,
      'last_message_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    return message;
  }

  static Future<Message> sendMediaMessage({
    required String conversationId,
    required String mediaUrl,
    required String mediaType,
    String caption = '',
    String? replyToMessageId,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': uid,
      'content': caption,
      'media_url': mediaUrl,
      'media_type': mediaType,
    };
    if (replyToMessageId != null) {
      payload['reply_to_message_id'] = replyToMessageId;
    }

    final row = await supabase.from('messages').insert(payload).select().single();
    final message = Message.fromJson(row);

    final String snippet;
    if (mediaType == 'voice') {
      snippet = '🎙️ Voice Note';
    } else if (mediaType == 'video') {
      snippet = '📹 Video';
    } else if (mediaType == 'gif') {
      snippet = '🎞️ GIF';
    } else if (mediaType == 'sticker') {
      snippet = '🎨 Sticker';
    } else {
      snippet = '📷 Photo';
    }

    await supabase.from('conversations').update({
      'last_message': caption.isNotEmpty ? '$snippet: $caption' : snippet,
      'last_message_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    return message;
  }

  static Future<Map<String, dynamic>> createConversation({
    required String buyerId,
    required String sellerId,
  }) async {
    final supabase = SupabaseService.instance;

    final existing = await supabase
        .from('conversations')
        .select('id')
        .or(
          'and(participant1_id.eq.$buyerId,participant2_id.eq.$sellerId),'
          'and(participant1_id.eq.$sellerId,participant2_id.eq.$buyerId)',
        )
        .maybeSingle();

    if (existing != null) {
      return {'conversation': existing};
    }

    final response = await supabase
        .from('conversations')
        .insert({
          'participant1_id': buyerId,
          'participant2_id': sellerId,
        })
        .select('id')
        .single();

    return {'conversation': response};
  }

  static Future<int> getUnreadCount() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return 0;

    final response = await supabase
        .from('messages')
        .select('id')
        .eq('receiver_id', uid)
        .eq('is_read', false);

    return response.length;
  }

  static Future<void> markAsRead(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    await supabase
        .from('messages')
        .update({'is_read': true})
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid);
  }

  /// Mark all undelivered messages in a conversation as seen
  static Future<void> markAsSeen(String conversationId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    await supabase
        .from('messages')
        .update({
          'status': 'seen',
          'is_read': true,
          'seen_at': DateTime.now().toIso8601String(),
        })
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid)
        .inFilter('status', ['sent', 'delivered']);
  }

  /// Update status of a specific message
  static Future<void> updateMessageStatus(String messageId, String status) async {
    final supabase = SupabaseService.instance;

    final update = <String, dynamic>{'status': status};
    if (status == 'seen') {
      update['seen_at'] = DateTime.now().toIso8601String();
    }

    await supabase
        .from('messages')
        .update(update)
        .eq('id', messageId);
  }

  /// Delete a message for the current user only (soft delete)
  static Future<void> deleteMessageForMe(String messageId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    await supabase.from('message_deletions').insert({
      'message_id': messageId,
      'user_id': uid,
    });
  }

  /// Delete a message for everyone (hard delete, sender only)
  static Future<void> deleteMessageForEveryone(String messageId) async {
    final supabase = SupabaseService.instance;

    // First get the message to check media and update conversation
    final msg = await supabase
        .from('messages')
        .select('conversation_id, media_url, sender_id')
        .eq('id', messageId)
        .single();

    // Delete media from storage if present
    final mediaUrl = msg['media_url'] as String?;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      try {
        await deleteMediaFromStorage(mediaUrl);
      } catch (_) {}
    }

    // Hard delete the message
    await supabase.from('messages').delete().eq('id', messageId);

    // Update conversation last_message if this was the last message
    final conversationId = msg['conversation_id'] as String;
    final lastMsg = await supabase
        .from('messages')
        .select('content, media_type, created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastMsg != null) {
      String snippet = (lastMsg['content'] as String?) ?? '';
      final mediaType = lastMsg['media_type'] as String?;
      if (snippet.isEmpty && mediaType != null) {
        if (mediaType == 'voice') {
          snippet = '🎙️ Voice Note';
        } else if (mediaType == 'video') {
          snippet = '📹 Video';
        } else {
          snippet = '📷 Photo';
        }
      }
      await supabase.from('conversations').update({
        'last_message': snippet,
        'last_message_at': lastMsg['created_at'],
      }).eq('id', conversationId);
    } else {
      await supabase.from('conversations').update({
        'last_message': null,
        'last_message_at': null,
      }).eq('id', conversationId);
    }
  }

  /// Delete media file from R2 storage
  static Future<void> deleteMediaFromStorage(String mediaUrl) async {
    await StorageService.deleteImage(mediaUrl);
  }

  static Future<void> updateConversationThemeColor(String conversationId, String? colorHex) async {
    final supabase = SupabaseService.instance;
    await supabase.from('conversations').update({
      'theme_color': colorHex,
    }).eq('id', conversationId);
  }

  static Future<Message> sendThemeChangeNotice({
    required String conversationId,
    required String themeName,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': uid,
      'content': themeName,
      'media_type': 'theme_change',
    };

    final row = await supabase.from('messages').insert(payload).select().single();
    final message = Message.fromJson(row);

    // Update last message snippet on the conversation
    await supabase.from('conversations').update({
      'last_message': 'Changed the chat theme to $themeName',
      'last_message_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    return message;
  }
}
