import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../services/message_service.dart';
import '../services/sound_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../services/local_notification_service.dart';

class MessageProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  List<Conversation> _archivedConversations = [];
  List<Message> _messages = [];
  Conversation? _activeConversation;
  Map<String, dynamic>? _pendingProductReference;
  bool _isLoading = false;
  bool _isLoadingArchived = false;
  bool _isLoadingMoreConversations = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreConversations = true;
  bool _hasMoreArchived = true;
  bool _hasMoreMessages = true;
  int _conversationPage = 0;
  int _archivedPage = 0;
  int _messagePage = 0;
  int _unreadCount = 0;
  int _unreadNotificationsCount = 0;
  String? _error;

  RealtimeChannel? _conversationsChannel;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _messagesGlobalChannel;

  List<Conversation> get conversations => _conversations;
  List<Conversation> get archivedConversations => _archivedConversations;
  List<Message> get messages => _messages;
  Conversation? get activeConversation => _activeConversation;
  Map<String, dynamic>? get pendingProductReference => _pendingProductReference;
  bool get isLoading => _isLoading;
  bool get isLoadingArchived => _isLoadingArchived;
  bool get isLoadingMoreConversations => _isLoadingMoreConversations;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreConversations => _hasMoreConversations;
  bool get hasMoreArchived => _hasMoreArchived;
  bool get hasMoreMessages => _hasMoreMessages;
  int get unreadCount => _unreadCount;
  int get unreadNotificationsCount => _unreadNotificationsCount;
  String? get error => _error;

  String? _currentUserId;

  MessageProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToGlobalRealtime();
      } else {
        _unsubscribeFromGlobalRealtime();
        _conversations = [];
        _archivedConversations = [];
        _messages = [];
        _activeConversation = null;
        _pendingProductReference = null;
        _unreadCount = 0;
        _unreadNotificationsCount = 0;
        _error = null;
        _currentUserId = null;
        notifyListeners();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToGlobalRealtime();
    }
  }

  void _subscribeToGlobalRealtime() {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    _unsubscribeFromGlobalRealtime();

    _conversationsChannel = SupabaseService.client
        .channel('public:conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            loadConversations();
            loadUnreadCount();
          },
        );
    _conversationsChannel!.subscribe();

    // Listen for new messages globally to show notifications and sync conversations list in realtime
    _messagesGlobalChannel = SupabaseService.client
        .channel('public:messages:global')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final data = payload.newRecord;
            final senderId = data['sender_id'] as String?;
            final conversationId = data['conversation_id'] as String?;
            final content = data['content'] as String? ?? '';
            final mediaType = data['media_type'] as String?;

            // Always update conversations list and unread count silently in realtime for any new message!
            if (conversationId != null) {
              loadConversations(silent: true);
              loadUnreadCount();
            }

            // Only notify for messages from other users
            if (senderId == null || senderId == userId) return;

            // Don't notify if user is viewing this conversation
            if (_activeConversation?.id == conversationId) return;

            // Get sender name from conversations
            String senderName = 'Someone';
            try {
              final conv = _conversations.firstWhere((c) => c.id == conversationId);
              senderName = conv.otherUserName ?? 'Someone';
            } catch (_) {}

            // Build notification body
            String body = content;
            if (body.isEmpty && mediaType != null) {
              body = mediaType == 'video' ? '📹 Sent a video' : '📷 Sent a photo';
            }
            if (body.isEmpty) body = 'Sent a message';

            await LocalNotificationService.showNotification(
              id: conversationId.hashCode,
              title: senderName,
              body: body,
              type: 'new_message',
            );

            // Play notification sound
            try {
              await SoundService.playSoundForType('new_message');
            } catch (_) {}
          },
        );
    _messagesGlobalChannel!.subscribe();

    _notificationsChannel = SupabaseService.client
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            loadUnreadNotificationsCount();
          },
        );
    _notificationsChannel!.subscribe();

    loadConversations();
    loadUnreadCount();
    loadUnreadNotificationsCount();
  }

  void _unsubscribeFromGlobalRealtime() {
    if (_conversationsChannel != null) {
      SupabaseService.client.removeChannel(_conversationsChannel!);
      _conversationsChannel = null;
    }
    if (_notificationsChannel != null) {
      SupabaseService.client.removeChannel(_notificationsChannel!);
      _notificationsChannel = null;
    }
    if (_messagesGlobalChannel != null) {
      SupabaseService.client.removeChannel(_messagesGlobalChannel!);
      _messagesGlobalChannel = null;
    }
  }

  Future<void> loadConversations({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _conversationPage = 0;
      _hasMoreConversations = true;
      notifyListeners();
    }

    try {
      final all = await MessageService.getConversations(offset: 0);
      _conversations = all.where((c) => !c.isArchived).toList();
      _hasMoreConversations = all.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadMoreConversations() async {
    if (_isLoadingMoreConversations || !_hasMoreConversations) return;
    _isLoadingMoreConversations = true;
    notifyListeners();

    try {
      _conversationPage++;
      final more = await MessageService.getConversations(offset: _conversationPage * 20);
      final nonArchived = more.where((c) => !c.isArchived).toList();
      _conversations.addAll(nonArchived);
      _hasMoreConversations = more.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMoreConversations = false;
      notifyListeners();
    }
  }

  Future<void> loadArchivedConversations({bool silent = false}) async {
    if (!silent) {
      _isLoadingArchived = true;
      _archivedPage = 0;
      _hasMoreArchived = true;
      notifyListeners();
    }

    try {
      _archivedConversations = await MessageService.getArchivedConversations(offset: 0);
      _hasMoreArchived = _archivedConversations.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) {
        _isLoadingArchived = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadMoreArchivedConversations() async {
    if (_isLoadingMoreMessages || !_hasMoreArchived) return;
    _isLoadingMoreMessages = true;
    notifyListeners();

    try {
      _archivedPage++;
      final more = await MessageService.getArchivedConversations(offset: _archivedPage * 20);
      _archivedConversations.addAll(more);
      _hasMoreArchived = more.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMoreMessages = false;
      notifyListeners();
    }
  }

  Future<void> archiveConversation(String conversationId) async {
    try {
      await MessageService.archiveConversation(conversationId);
      // Move conversation from main list to archived list
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        final conv = _conversations.removeAt(idx);
        _archivedConversations.insert(0, Conversation(
          id: conv.id,
          otherUserId: conv.otherUserId,
          otherUserName: conv.otherUserName,
          otherUserAvatar: conv.otherUserAvatar,
          otherUserVerified: conv.otherUserVerified,
          otherBusinessName: conv.otherBusinessName,
          lastMessage: conv.lastMessage,
          lastMessageAt: conv.lastMessageAt,
          unreadCount: conv.unreadCount,
          isOnline: conv.isOnline,
          isArchived: true,
        ));
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> unarchiveConversation(String conversationId) async {
    try {
      await MessageService.unarchiveConversation(conversationId);
      // Move conversation from archived list back to main list
      final idx = _archivedConversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        final conv = _archivedConversations.removeAt(idx);
        _conversations.insert(0, Conversation(
          id: conv.id,
          otherUserId: conv.otherUserId,
          otherUserName: conv.otherUserName,
          otherUserAvatar: conv.otherUserAvatar,
          otherUserVerified: conv.otherUserVerified,
          otherBusinessName: conv.otherBusinessName,
          lastMessage: conv.lastMessage,
          lastMessageAt: conv.lastMessageAt,
          unreadCount: conv.unreadCount,
          isOnline: conv.isOnline,
          isArchived: false,
        ));
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadMessages(String conversationId) async {
    _isLoading = true;
    _messagePage = 0;
    _hasMoreMessages = true;
    notifyListeners();

    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }

    try {
      _messages = await MessageService.getMessages(conversationId, offset: 0);
      _hasMoreMessages = _messages.length >= 20;
      // Mark all messages from other user as seen
      await MessageService.markAsSeen(conversationId);
      loadUnreadCount();

      // Clear local conversation unread count immediately
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        final oldConv = _conversations[idx];
        _conversations[idx] = Conversation(
          id: oldConv.id,
          otherUserId: oldConv.otherUserId,
          otherUserName: oldConv.otherUserName,
          otherUserAvatar: oldConv.otherUserAvatar,
          otherUserVerified: oldConv.otherUserVerified,
          otherBusinessName: oldConv.otherBusinessName,
          lastMessage: oldConv.lastMessage,
          lastMessageAt: oldConv.lastMessageAt,
          unreadCount: 0,
          isOnline: oldConv.isOnline,
        );
      }

      _messagesChannel = SupabaseService.client
          .channel('public:messages:$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (payload) {
              try {
                final newMessage = Message.fromJson(payload.newRecord);
                if (!_messages.any((m) => m.id == newMessage.id)) {
                  _messages.add(newMessage);
                  notifyListeners();

                  if (newMessage.senderId != SupabaseService.auth.currentUser?.id) {
                    MessageService.markAsRead(conversationId);
                    loadUnreadCount();
                    SoundService.playSoundForType('in_chat_message');
                  }
                }
              } catch (_) {}
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (payload) {
              final oldId = payload.oldRecord['id'] as String?;
              if (oldId != null) {
                _messages.removeWhere((m) => m.id == oldId);
                notifyListeners();
              }
            },
          );
      _messagesChannel!.subscribe();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(String conversationId) async {
    if (_isLoadingMoreMessages || !_hasMoreMessages) return;
    _isLoadingMoreMessages = true;
    notifyListeners();

    try {
      _messagePage++;
      final more = await MessageService.getMessages(
        conversationId,
        offset: _messagePage * 20,
      );
      _messages.insertAll(0, more);
      _hasMoreMessages = more.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMoreMessages = false;
      notifyListeners();
    }
  }

  void setActiveConversation(Conversation? conversation) {
    _activeConversation = conversation;
    notifyListeners();
  }

  void clearActiveConversation() {
    _activeConversation = null;
    _messages = [];
    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }
    notifyListeners();
  }

  /// Clean up conversation state without notifying — safe to call from dispose()
  void disposeConversation() {
    _activeConversation = null;
    _messages = [];
    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }
  }

  Future<void> sendMessage(String content, {Map<String, dynamic>? productReference, String? replyToMessageId}) async {
    if (_activeConversation == null) return;

    try {
      final message = await MessageService.sendMessage(
        conversationId: _activeConversation!.id,
        content: content,
        productReference: productReference,
        replyToMessageId: replyToMessageId,
      );
      // Add message immediately so it appears without waiting for Realtime
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        notifyListeners();
      }
      // Instantly update local conversation list so the sent message and timestamp propagate immediately
      loadConversations(silent: true);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendMediaMessage({
    required String mediaUrl,
    required String mediaType,
    String caption = '',
    String? replyToMessageId,
  }) async {
    if (_activeConversation == null) return;

    try {
      final message = await MessageService.sendMediaMessage(
        conversationId: _activeConversation!.id,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );
      // Add message immediately so it appears without waiting for Realtime
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        notifyListeners();
      }
      // Instantly update local conversation list so the sent media message propagates immediately
      loadConversations(silent: true);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> createAndOpenConversation({
    required String buyerId,
    required String sellerId,
    Map<String, dynamic>? productReference,
  }) async {
    try {
      final result = await MessageService.createConversation(
        buyerId: buyerId,
        sellerId: sellerId,
      );
      final conversationData = result['conversation'] as Map<String, dynamic>;
      final conversationId = conversationData['id'] as String;

      // Fetch other participant's details to populate header information
      final sellerResponse = await SupabaseService.client
          .from('users')
          .select('full_name, avatar_url, is_verified')
          .eq('id', sellerId)
          .single();

      // Fetch business name
      String? businessName;
      try {
        final bizResponse = await SupabaseService.client
            .from('business_profiles')
            .select('business_name')
            .eq('seller_id', sellerId)
            .maybeSingle();
        businessName = bizResponse?['business_name'] as String?;
      } catch (_) {}

      final conv = Conversation(
        id: conversationId,
        otherUserId: sellerId,
        otherUserName: sellerResponse['full_name'] as String?,
        otherUserAvatar: sellerResponse['avatar_url'] as String?,
        otherUserVerified: sellerResponse['is_verified'] as bool? ?? false,
        otherBusinessName: businessName,
      );
      _pendingProductReference = productReference;
      setActiveConversation(conv);
      await loadMessages(conversationId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void consumePendingProductReference() {
    _pendingProductReference = null;
    notifyListeners();
  }

  /// Delete a message for the current user only
  Future<void> deleteMessageForMe(String messageId) async {
    try {
      await MessageService.deleteMessageForMe(messageId);
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Delete multiple messages for the current user only
  Future<void> deleteMessagesForMe(List<String> messageIds) async {
    try {
      for (final id in messageIds) {
        await MessageService.deleteMessageForMe(id);
      }
      _messages.removeWhere((m) => messageIds.contains(m.id));
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Delete a message for everyone (hard delete, sender only)
  Future<void> deleteMessageForEveryone(String messageId) async {
    try {
      await MessageService.deleteMessageForEveryone(messageId);
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Delete multiple messages for everyone (hard delete, sender only)
  Future<void> deleteMessagesForEveryone(List<String> messageIds) async {
    try {
      for (final id in messageIds) {
        await MessageService.deleteMessageForEveryone(id);
      }
      _messages.removeWhere((m) => messageIds.contains(m.id));
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadUnreadCount() async {
    try {
      _unreadCount = await MessageService.getUnreadCount();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadUnreadNotificationsCount() async {
    try {
      _unreadNotificationsCount = await NotificationService.getUnreadCount();
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _unsubscribeFromGlobalRealtime();
    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }
}
