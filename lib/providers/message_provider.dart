import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../services/message_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../services/local_notification_service.dart';
import '../services/local_db_service.dart';
import '../providers/block_provider.dart';

/// Params for one fire-and-forget outgoing message, kept so a failed send
/// can be retried from the bubble without losing its place in the queue.
/// Reply-quote display fields live on the optimistic Message itself, so the
/// task only keeps what the network calls need.
class _PendingSend {
  final String kind; // 'text', 'upload', 'remote'
  final String conversationId;
  final String content;
  final Map<String, dynamic>? productReference;
  final String? replyToMessageId;
  final String? mediaType;
  final String? mediaSource;
  final Uint8List? bytes;
  final String? extension;
  final String? folder;
  final Uint8List? thumbnailBytes;
  final String? remoteUrl;
  final void Function(String url)? onUploaded;

  const _PendingSend({
    required this.kind,
    required this.conversationId,
    this.content = '',
    this.productReference,
    this.replyToMessageId,
    this.mediaType,
    this.mediaSource,
    this.bytes,
    this.extension,
    this.folder,
    this.thumbnailBytes,
    this.remoteUrl,
    this.onUploaded,
  });
}

class MessageProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  List<Conversation> _archivedConversations = [];
  List<Message> _messages = [];
  Conversation? _activeConversation;
  Map<String, dynamic>? _pendingProductReference;
  /// Maps conversationId → the DateTime when the user deleted that chat.
  /// Messages before this timestamp are hidden (WhatsApp-style).
  final Map<String, DateTime> _hiddenAtMap = {};
  bool _isLoading = false;
  bool _isLoadingMessages = false;
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
  int _unreadServiceNotificationsCount = 0;
  int _unreadExploreNotificationsCount = 0;
  String? _error;
  bool _initialized = false;
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;

  /// Ephemeral theme-change notice shown as an inline divider (not persisted).
  String? _themeChangeNotice;
  DateTime? _themeChangeNoticeTime;

  RealtimeChannel? _conversationsChannel;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _messagesGlobalChannel;
  RealtimeChannel? _usersChannel;
  Timer? _presenceTimer;
  Timer? _statusUpdateTimer;

  List<Conversation> get conversations => _conversations;
  List<Conversation> get archivedConversations => _archivedConversations;
  List<Message> get messages => _messages;
  Conversation? get activeConversation => _activeConversation;
  Map<String, dynamic>? get pendingProductReference => _pendingProductReference;
  bool get isLoading => _isLoading;
  /// True only while messages for the active conversation are loading.
  /// Separate from [isLoading] so the conversation list and message list
  /// never share the same loading flag.
  bool get isLoadingMessages => _isLoadingMessages;
  bool get isLoadingArchived => _isLoadingArchived;
  bool get isLoadingMoreConversations => _isLoadingMoreConversations;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreConversations => _hasMoreConversations;
  bool get hasMoreArchived => _hasMoreArchived;
  bool get hasMoreMessages => _hasMoreMessages;
  int get unreadCount => _unreadCount;
  int get unreadNotificationsCount => _unreadNotificationsCount;
  int get unreadServiceNotificationsCount => _unreadServiceNotificationsCount;
  int get unreadExploreNotificationsCount => _unreadExploreNotificationsCount;
  String? get error => _error;
  bool get isInitialized => _initialized;
  bool get isOtherUserTyping => _isOtherUserTyping;

  /// Params for every in-flight fire-and-forget send, keyed by the
  /// optimistic message id. Kept for retry after a failure.
  final Map<String, _PendingSend> _pendingSends = {};

  /// How many optimistic messages are still sending in [conversationId].
  /// The chat input uses this for a progress badge — it never blocks typing.
  int pendingCountFor(String conversationId) {
    var n = 0;
    for (final m in _messages) {
      if (m.conversationId == conversationId && m.isSending) n++;
    }
    return n;
  }

  /// Ephemeral theme-change notice (null when none).
  String? get themeChangeNotice => _themeChangeNotice;
  DateTime? get themeChangeNoticeTime => _themeChangeNoticeTime;

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
        _hiddenAtMap.clear();
        _unreadCount = 0;
        _unreadNotificationsCount = 0;
        _unreadServiceNotificationsCount = 0;
        _unreadExploreNotificationsCount = 0;
        _error = null;
        _currentUserId = null;
        _initialized = false;
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
            loadConversations(silent: true);
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
            // getConversations already handles resurfacing hidden chats when
            // lastMessageAt > hiddenAt, so no extra logic needed here.
            if (conversationId != null) {
              loadConversations(silent: true); // ignore: unawaited_futures
              loadUnreadCount(); // ignore: unawaited_futures
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

    // Subscribe to users status updates in realtime
    _usersChannel = SupabaseService.client
        .channel('public:users')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            final data = payload.newRecord;
            final userId = data['id'] as String?;
            final lastSeenStr = data['last_seen'] as String?;
            if (userId != null && lastSeenStr != null) {
              _updateUserStatusInMemory(userId, DateTime.parse(lastSeenStr));
            }
          },
        );
    _usersChannel!.subscribe();

    _startPresenceAndStatusTimers();

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
    if (_usersChannel != null) {
      SupabaseService.client.removeChannel(_usersChannel!);
      _usersChannel = null;
    }
    _stopPresenceAndStatusTimers();
  }

  void _startPresenceAndStatusTimers() {
    _presenceTimer?.cancel();
    _statusUpdateTimer?.cancel();

    // Update presence immediately, then every 30 seconds
    _updateUserPresence();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateUserPresence();
    });

    // Notify listeners every 10 seconds to update dynamic isOnline status and last seen formatting
    var tick = 0;
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      notifyListeners();
      // Every 60s, re-fetch peers' last_seen directly. This heals presence
      // when a realtime users-table event was missed (channel error,
      // backgrounding, cold start), so an active user cannot stay stuck
      // appearing offline.
      tick++;
      if (tick % 6 == 0) {
        _refreshPeersPresence(); // ignore: unawaited_futures
      }
    });
  }

  void _stopPresenceAndStatusTimers() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = null;
  }

  Future<void> _updateUserPresence() async {
    final userId = _currentUserId ?? SupabaseService.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseService.client
          .from('users')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (_) {}
  }

  /// Lightweight heal for missed realtime presence events: fetches the
  /// current last_seen for every peer shown in the lists (plus the open
  /// chat) and applies it in memory without a full conversation reload.
  Future<void> _refreshPeersPresence() async {
    try {
      final ids = <String>{};
      for (final c in _conversations) {
        ids.add(c.otherUserId);
      }
      for (final c in _archivedConversations) {
        ids.add(c.otherUserId);
      }
      final active = _activeConversation;
      if (active != null) ids.add(active.otherUserId);
      if (ids.isEmpty) return;

      final rows = await SupabaseService.client
          .from('users')
          .select('id, last_seen')
          .inFilter('id', ids.toList());
      for (final row in rows) {
        final id = row['id'] as String?;
        final lastSeenRaw = row['last_seen'] as String?;
        if (id == null || lastSeenRaw == null) continue;
        DateTime? before;
        for (final c in _conversations) {
          if (c.otherUserId == id) {
            before = c.otherUserLastSeen;
            break;
          }
        }
        if (before == null) {
          for (final c in _archivedConversations) {
            if (c.otherUserId == id) {
              before = c.otherUserLastSeen;
              break;
            }
          }
        }
        before ??= active?.otherUserId == id ? active?.otherUserLastSeen : null;
        final fresh = DateTime.parse(lastSeenRaw);
        if (before == null || fresh.isAfter(before)) {
          // Reuse the realtime path so list + archived + active stay in sync.
          _updateUserStatusInMemory(id, fresh);
        }
      }
    } catch (_) {}
  }

  void _updateUserStatusInMemory(String userId, DateTime lastSeen) {
    bool updated = false;

    // Update conversations list
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].otherUserId == userId) {
        _conversations[i] = Conversation(
          id: _conversations[i].id,
          otherUserId: _conversations[i].otherUserId,
          otherUserName: _conversations[i].otherUserName,
          otherUserAvatar: _conversations[i].otherUserAvatar,
          otherUserVerified: _conversations[i].otherUserVerified,
          otherBusinessName: _conversations[i].otherBusinessName,
          lastMessage: _conversations[i].lastMessage,
          lastMessageAt: _conversations[i].lastMessageAt,
          unreadCount: _conversations[i].unreadCount,
          isArchived: _conversations[i].isArchived,
          hiddenAt: _conversations[i].hiddenAt,
          otherUserLastSeen: lastSeen,
          themeColor: _conversations[i].themeColor,
        );
        updated = true;
      }
    }

    // Update archived conversations list
    for (int i = 0; i < _archivedConversations.length; i++) {
      if (_archivedConversations[i].otherUserId == userId) {
        _archivedConversations[i] = Conversation(
          id: _archivedConversations[i].id,
          otherUserId: _archivedConversations[i].otherUserId,
          otherUserName: _archivedConversations[i].otherUserName,
          otherUserAvatar: _archivedConversations[i].otherUserAvatar,
          otherUserVerified: _archivedConversations[i].otherUserVerified,
          otherBusinessName: _archivedConversations[i].otherBusinessName,
          lastMessage: _archivedConversations[i].lastMessage,
          lastMessageAt: _archivedConversations[i].lastMessageAt,
          unreadCount: _archivedConversations[i].unreadCount,
          isArchived: _archivedConversations[i].isArchived,
          hiddenAt: _archivedConversations[i].hiddenAt,
          otherUserLastSeen: lastSeen,
          themeColor: _archivedConversations[i].themeColor,
        );
        updated = true;
      }
    }

    // Update active conversation
    if (_activeConversation != null && _activeConversation!.otherUserId == userId) {
      _activeConversation = Conversation(
        id: _activeConversation!.id,
        otherUserId: _activeConversation!.otherUserId,
        otherUserName: _activeConversation!.otherUserName,
        otherUserAvatar: _activeConversation!.otherUserAvatar,
        otherUserVerified: _activeConversation!.otherUserVerified,
        otherBusinessName: _activeConversation!.otherBusinessName,
        lastMessage: _activeConversation!.lastMessage,
        lastMessageAt: _activeConversation!.lastMessageAt,
        unreadCount: _activeConversation!.unreadCount,
        isArchived: _activeConversation!.isArchived,
        hiddenAt: _activeConversation!.hiddenAt,
        otherUserLastSeen: lastSeen,
        themeColor: _activeConversation!.themeColor,
      );
      updated = true;
    }

    if (updated) {
      notifyListeners();
    }
  }

  Future<void> ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    await loadConversations(silent: _conversations.isNotEmpty);
  }

  Future<void> loadConversations({bool silent = false}) async {
    final userId = _currentUserId ?? SupabaseService.auth.currentUser?.id;

    // Cache-first: show cached data immediately if available
    if (_conversations.isEmpty && userId != null) {
      try {
        final cached = await LocalDbService.instance.getCachedConversations(userId);
        if (cached.isNotEmpty) {
          _conversations = BlockProvider.instance.filterConversations(cached.where((c) => !c.isArchived).toList());
          _hasMoreConversations = true;
          notifyListeners();
        } else if (!silent) {
          _isLoading = true;
          _conversationPage = 0;
          _hasMoreConversations = true;
          notifyListeners();
        }
      } catch (_) {
        if (!silent) {
          _isLoading = true;
          notifyListeners();
        }
      }
    } else if (!silent) {
      _isLoading = true;
      _conversationPage = 0;
      _hasMoreConversations = true;
      notifyListeners();
    }

    try {
      final all = await MessageService.getConversations(offset: 0);
      _conversations = BlockProvider.instance.filterConversations(all.where((c) => !c.isArchived).toList());
      _hasMoreConversations = all.length >= 20;

      // Update active conversation in case it changed (like theme_color updates)
      if (_activeConversation != null) {
        try {
          final matching = all.firstWhere((c) => c.id == _activeConversation!.id);
          if (matching.themeColor != _activeConversation!.themeColor) {
            // Other user changed the theme — show ephemeral notice
            final hex = matching.themeColor;
            String? themeName;
            switch (hex) {
              case '#7C3AED': themeName = 'Default Purple'; break;
              case '#F97316': themeName = 'Orange'; break;
              case '#10B981': themeName = 'Mint'; break;
              case '#0D9488': themeName = 'Teal'; break;
              case '#0EA5E9': themeName = 'Sky Blue'; break;
              case '#2563EB': themeName = 'Royal Blue'; break;
              case '#8B5CF6': themeName = 'Lavender'; break;
              case '#EC4899': themeName = 'Rose Pink'; break;
              case '#DC2626': themeName = 'Crimson'; break;
              case '#F59E0B': themeName = 'Amber Gold'; break;
              case '#15803D': themeName = 'Forest'; break;
              case '#374151': themeName = 'Charcoal'; break;
            }
            if (themeName != null) {
              _themeChangeNotice = 'Changed the chat theme to $themeName';
              _themeChangeNoticeTime = DateTime.now();
            }
          }
          _activeConversation = matching;
        } catch (_) {}
      }

      // Update cache silently
      if (userId != null) {
        LocalDbService.instance.cacheConversations(userId, all); // ignore: unawaited_futures
      }
    } catch (e) {
      // If network fails and cache exists, silently absorb
      if (_conversations.isEmpty) _error = e.toString();
    } finally {
      if (!silent) _isLoading = false;
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
      _conversations.addAll(BlockProvider.instance.filterConversations(nonArchived));
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

  /// Hide a conversation for the current user only (soft-delete from their view).
  /// Stores hidden_at so old messages stay hidden even if the conversation
  /// resurfaces when the other user sends a new message (WhatsApp-style).
  Future<void> hideConversation(String conversationId) async {
    try {
      final hiddenAt = await MessageService.hideConversation(conversationId);
      _hiddenAtMap[conversationId] = hiddenAt;
      _conversations.removeWhere((c) => c.id == conversationId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
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
          hiddenAt: conv.hiddenAt,
          otherUserLastSeen: conv.otherUserLastSeen,
          themeColor: conv.themeColor,
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
          hiddenAt: conv.hiddenAt,
          otherUserLastSeen: conv.otherUserLastSeen,
          themeColor: conv.themeColor,
        ));
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadMessages(String conversationId) async {
    _isLoadingMessages = true;
    _messagePage = 0;
    _hasMoreMessages = true;
    _messages = []; // Clear stale messages immediately so the skeleton shows
    notifyListeners();

    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!); // ignore: unawaited_futures
      _messagesChannel = null;
    }

    try {
      // Use hiddenAt from the active conversation (set when user deleted the chat)
      // so only messages after that timestamp are shown — WhatsApp-style.
      final hiddenAt = _activeConversation?.hiddenAt ?? _hiddenAtMap[conversationId];

      // Cache-first: show cached messages immediately
      try {
        final cached = await LocalDbService.instance.getCachedMessages(conversationId);
        if (cached.isNotEmpty) {
          _messages = cached;
          _hasMoreMessages = true;
          notifyListeners();
        }
      } catch (_) {}

      // Fetch from network
      final networkMessages = await MessageService.getMessages(conversationId, offset: 0, hiddenAt: hiddenAt);
      _messages = networkMessages;
      _hasMoreMessages = _messages.length >= 20;

      // Fetch latest conversation properties (like theme_color) from database
      try {
        final latestConv = await MessageService.getConversationById(conversationId);
        if (latestConv != null) {
          // Update local state in conversations list
          for (int i = 0; i < _conversations.length; i++) {
            if (_conversations[i].id == conversationId) {
              _conversations[i] = latestConv;
            }
          }
          for (int i = 0; i < _archivedConversations.length; i++) {
            if (_archivedConversations[i].id == conversationId) {
              _archivedConversations[i] = latestConv;
            }
          }
          // Update active conversation
          _activeConversation = latestConv;
        }
      } catch (_) {}

      // Mark all messages from other user as seen
      await MessageService.markAsSeen(conversationId);
      loadUnreadCount(); // ignore: unawaited_futures

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
          isArchived: oldConv.isArchived,
          hiddenAt: oldConv.hiddenAt,
          otherUserLastSeen: oldConv.otherUserLastSeen,
          themeColor: oldConv.themeColor,
        );
      }

      final archIdx = _archivedConversations.indexWhere((c) => c.id == conversationId);
      if (archIdx != -1) {
        final oldConv = _archivedConversations[archIdx];
        _archivedConversations[archIdx] = Conversation(
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
          isArchived: oldConv.isArchived,
          hiddenAt: oldConv.hiddenAt,
          otherUserLastSeen: oldConv.otherUserLastSeen,
          themeColor: oldConv.themeColor,
        );
      }

      if (_activeConversation != null && _activeConversation!.id == conversationId) {
        _activeConversation = Conversation(
          id: _activeConversation!.id,
          otherUserId: _activeConversation!.otherUserId,
          otherUserName: _activeConversation!.otherUserName,
          otherUserAvatar: _activeConversation!.otherUserAvatar,
          otherUserVerified: _activeConversation!.otherUserVerified,
          otherBusinessName: _activeConversation!.otherBusinessName,
          lastMessage: _activeConversation!.lastMessage,
          lastMessageAt: _activeConversation!.lastMessageAt,
          unreadCount: 0,
          isOnline: _activeConversation!.isOnline,
          isArchived: _activeConversation!.isArchived,
          hiddenAt: _activeConversation!.hiddenAt,
          otherUserLastSeen: _activeConversation!.otherUserLastSeen,
          themeColor: _activeConversation!.themeColor,
        );
      }

      // Sync local SQLite conversations cache
      final userId = _currentUserId ?? SupabaseService.auth.currentUser?.id;
      if (userId != null) {
        final all = [..._conversations, ..._archivedConversations];
        await LocalDbService.instance.cacheConversations(userId, all); // ignore: unawaited_futures
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
          )
          .onBroadcast(
            event: 'typing',
            callback: (payload) {
              final senderId = payload['sender_id'] as String?;
              final isTyping = payload['is_typing'] as bool? ?? false;
              if (senderId != null && senderId != SupabaseService.auth.currentUser?.id) {
                _typingTimer?.cancel();
                if (isTyping) {
                  _isOtherUserTyping = true;
                  _typingTimer = Timer(const Duration(seconds: 10), () {
                    _isOtherUserTyping = false;
                    notifyListeners();
                  });
                } else {
                  _isOtherUserTyping = false;
                }
                notifyListeners();
              }
            },
          );
      _messagesChannel!.subscribe();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(String conversationId) async {
    if (_isLoadingMoreMessages || !_hasMoreMessages) return;
    _isLoadingMoreMessages = true;
    notifyListeners();

    try {
      _messagePage++;
      final hiddenAt = _activeConversation?.hiddenAt ?? _hiddenAtMap[conversationId];
      final more = await MessageService.getMessages(
        conversationId,
        offset: _messagePage * 20,
        hiddenAt: hiddenAt,
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
    if (conversation == null) {
      _activeConversation = null;
      notifyListeners();
      return;
    }

    Conversation resolvedConversation = conversation;
    final idx = _conversations.indexWhere((c) => c.id == conversation.id);
    if (idx != -1) {
      resolvedConversation = _conversations[idx];
    } else {
      final archIdx = _archivedConversations.indexWhere((c) => c.id == conversation.id);
      if (archIdx != -1) {
        resolvedConversation = _archivedConversations[archIdx];
      }
    }

    if (conversation.themeColor != null && resolvedConversation.themeColor == null) {
      resolvedConversation = conversation;
    }

    _activeConversation = resolvedConversation;
    notifyListeners();
  }

  void clearActiveConversation() {
    _activeConversation = null;
    _messages = [];
    _typingTimer?.cancel();
    _isOtherUserTyping = false;
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
    _typingTimer?.cancel();
    _isOtherUserTyping = false;
    if (_messagesChannel != null) {
      SupabaseService.client.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }
  }

  void sendTypingStatus(bool isTyping) {
    if (_messagesChannel == null) return;
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    _messagesChannel!.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'sender_id': userId,
        'is_typing': isTyping,
      },
    );
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
      loadConversations(silent: true); // ignore: unawaited_futures
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
    String? mediaSource,
  }) async {
    if (_activeConversation == null) return;

    try {
      final message = await MessageService.sendMediaMessage(
        conversationId: _activeConversation!.id,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: caption,
        replyToMessageId: replyToMessageId,
        mediaSource: mediaSource,
      );
      // Add message immediately so it appears without waiting for Realtime
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        notifyListeners();
      }
      // Instantly update local conversation list so the sent media message propagates immediately
      loadConversations(silent: true); // ignore: unawaited_futures
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ── Fire-and-forget send queue ──────────────────────────────────────
  // Every send inserts an optimistic message synchronously (so previews
  // appear instantly and in tap order) and finishes in the background.
  // The chat input never blocks: callers must NOT await these methods.

  /// Queues a text (or product-reference) message. Returns the optimistic id.
  String queueTextMessage({
    required String conversationId,
    required String senderId,
    required String content,
    Map<String, dynamic>? productReference,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderName,
    String? replyToMediaUrl,
    String? replyToMediaType,
  }) {
    final pendingId = 'pending_${const Uuid().v4()}';
    final optimistic = Message(
      id: pendingId,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      productReference: _refFromMap(productReference),
      createdAt: DateTime.now(),
      status: 'sending',
      replyToMessageId: replyToMessageId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      replyToMediaUrl: replyToMediaUrl,
      replyToMediaType: replyToMediaType,
    );
    _pendingSends[pendingId] = _PendingSend(
      kind: 'text',
      conversationId: conversationId,
      content: content,
      productReference: productReference,
      replyToMessageId: replyToMessageId,
    );
    _insertOptimistic(optimistic);
    _runTextTask(pendingId); // ignore: unawaited_futures
    return pendingId;
  }

  /// Queues a media message whose bytes are uploaded in the background.
  /// [previewBytes] shows instantly in the bubble (image bytes, or the
  /// video thumbnail frame). Returns the optimistic id.
  String queueMediaUpload({
    required String conversationId,
    required String senderId,
    required Uint8List bytes,
    required String folder,
    required String extension,
    required String mediaType,
    String caption = '',
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderName,
    String? replyToMediaUrl,
    String? replyToMediaType,
    String? mediaSource,
    Uint8List? thumbnailBytes,
    Uint8List? previewBytes,
    void Function(String url)? onUploaded,
  }) {
    final pendingId = 'pending_${const Uuid().v4()}';
    final optimistic = Message(
      id: pendingId,
      conversationId: conversationId,
      senderId: senderId,
      content: caption,
      mediaType: mediaType,
      mediaSource: mediaSource,
      createdAt: DateTime.now(),
      status: 'sending',
      replyToMessageId: replyToMessageId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      replyToMediaUrl: replyToMediaUrl,
      replyToMediaType: replyToMediaType,
      localPreviewBytes: previewBytes ?? thumbnailBytes,
    );
    _pendingSends[pendingId] = _PendingSend(
      kind: 'upload',
      conversationId: conversationId,
      content: caption,
      replyToMessageId: replyToMessageId,
      mediaType: mediaType,
      mediaSource: mediaSource,
      bytes: bytes,
      extension: extension,
      folder: folder,
      thumbnailBytes: thumbnailBytes,
      onUploaded: onUploaded,
    );
    _insertOptimistic(optimistic);
    _runUploadTask(pendingId); // ignore: unawaited_futures
    return pendingId;
  }

  /// Queues a message whose media already lives at a remote URL (GIFs,
  /// stickers). No upload — only the row insert runs in the background.
  String queueRemoteMediaMessage({
    required String conversationId,
    required String senderId,
    required String mediaUrl,
    required String mediaType,
    String caption = '',
    String? replyToMessageId,
    String? mediaSource,
  }) {
    final pendingId = 'pending_${const Uuid().v4()}';
    final optimistic = Message(
      id: pendingId,
      conversationId: conversationId,
      senderId: senderId,
      content: caption,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaSource: mediaSource,
      createdAt: DateTime.now(),
      status: 'sending',
      replyToMessageId: replyToMessageId,
    );
    _pendingSends[pendingId] = _PendingSend(
      kind: 'remote',
      conversationId: conversationId,
      content: caption,
      replyToMessageId: replyToMessageId,
      mediaType: mediaType,
      mediaSource: mediaSource,
      remoteUrl: mediaUrl,
    );
    _insertOptimistic(optimistic);
    _runRemoteTask(pendingId); // ignore: unawaited_futures
    return pendingId;
  }

  /// Retries a failed optimistic message, keeping its position in the list.
  void retryPending(String pendingId) {
    final task = _pendingSends[pendingId];
    if (task == null) return;
    final idx = _messages.indexWhere((m) => m.id == pendingId);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].withStatus('sending');
    notifyListeners();
    switch (task.kind) {
      case 'text':
        _runTextTask(pendingId); // ignore: unawaited_futures
        break;
      case 'upload':
        _runUploadTask(pendingId); // ignore: unawaited_futures
        break;
      case 'remote':
        _runRemoteTask(pendingId); // ignore: unawaited_futures
        break;
    }
  }

  /// Inserts the optimistic bubble synchronously and nudges the
  /// conversation snippet so the list preview updates instantly.
  void _insertOptimistic(Message optimistic) {
    // Only touch the message list when its conversation is open — never
    // leak an optimistic bubble into another chat's list.
    if (_activeConversation != null &&
        _activeConversation!.id == optimistic.conversationId) {
      _messages.add(optimistic);
    }
    _touchConversationSnippet(
      optimistic.conversationId,
      _snippetFor(optimistic),
    );
    notifyListeners();
  }

  /// Converts the outgoing product-reference map into a display model for
  /// the optimistic bubble. Returns null when the map doesn't match the
  /// ProductReference shape — the server insert still uses the raw map.
  ProductReference? _refFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    try {
      return ProductReference.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  String _snippetFor(Message m) {    if (m.mediaType == 'voice') return '🎙️ Voice Note';
    if (m.mediaType == 'video') return '📹 Video';
    if (m.mediaType == 'gif') return '🎞️ GIF';
    if (m.mediaType == 'sticker') return '🎨 Sticker';
    if (m.mediaType == 'image') {
      return m.content.isNotEmpty ? '📷 Photo: ${m.content}' : '📷 Photo';
    }
    if (m.productReference != null) return '📇 Shared: ${m.productReference!.title}';
    return m.content;
  }

  void _touchConversationSnippet(String conversationId, String snippet) {
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversationId) {
        final c = _conversations[i];
        _conversations[i] = Conversation(
          id: c.id,
          otherUserId: c.otherUserId,
          otherUserName: c.otherUserName,
          otherUserAvatar: c.otherUserAvatar,
          otherUserVerified: c.otherUserVerified,
          otherBusinessName: c.otherBusinessName,
          lastMessage: snippet,
          lastMessageAt: DateTime.now(),
          unreadCount: c.unreadCount,
          isArchived: c.isArchived,
          hiddenAt: c.hiddenAt,
          otherUserLastSeen: c.otherUserLastSeen,
          themeColor: c.themeColor,
        );
        break;
      }
    }
  }

  Future<void> _runTextTask(String pendingId) async {
    final task = _pendingSends[pendingId];
    if (task == null) return;
    try {
      final server = await MessageService.sendMessage(
        conversationId: task.conversationId,
        content: task.content,
        productReference: task.productReference,
        replyToMessageId: task.replyToMessageId,
      );
      _resolvePending(pendingId, server);
    } catch (_) {
      _failPending(pendingId);
    }
  }

  Future<void> _runUploadTask(String pendingId) async {
    final task = _pendingSends[pendingId];
    if (task == null || task.bytes == null) {
      _failPending(pendingId);
      return;
    }
    try {
      var mediaUrl = await StorageService.uploadImageBytes(
        bytes: task.bytes!,
        folder: task.folder ?? 'chat-media/images',
        extension: task.extension ?? 'jpg',
      );
      if (task.mediaType == 'video' && task.thumbnailBytes != null) {
        try {
          final thumbUrl = await StorageService.uploadImageBytes(
            bytes: task.thumbnailBytes!,
            folder: 'chat-media/thumbnails',
            extension: 'jpg',
          );
          mediaUrl = '$mediaUrl|$thumbUrl';
        } catch (_) {}
      }
      task.onUploaded?.call(mediaUrl);
      final server = await MessageService.sendMediaMessage(
        conversationId: task.conversationId,
        mediaUrl: mediaUrl,
        mediaType: task.mediaType ?? 'image',
        caption: task.content,
        replyToMessageId: task.replyToMessageId,
        mediaSource: task.mediaSource,
      );
      _resolvePending(pendingId, server);
    } catch (_) {
      _failPending(pendingId);
    }
  }

  Future<void> _runRemoteTask(String pendingId) async {
    final task = _pendingSends[pendingId];
    if (task == null || task.remoteUrl == null) {
      _failPending(pendingId);
      return;
    }
    try {
      final server = await MessageService.sendMediaMessage(
        conversationId: task.conversationId,
        mediaUrl: task.remoteUrl!,
        mediaType: task.mediaType ?? 'gif',
        caption: task.content,
        replyToMessageId: task.replyToMessageId,
        mediaSource: task.mediaSource,
      );
      _resolvePending(pendingId, server);
    } catch (_) {
      _failPending(pendingId);
    }
  }

  /// Swaps the optimistic bubble for the confirmed server row in place,
  /// so queued messages settle in the order they were sent even when an
  /// earlier upload finishes after a later one.
  void _resolvePending(String pendingId, Message server) {
    _pendingSends.remove(pendingId);
    final idx = _messages.indexWhere((m) => m.id == pendingId);
    if (idx != -1) {
      _messages[idx] = server;
      notifyListeners();
    } else if (_activeConversation != null &&
        _activeConversation!.id == server.conversationId &&
        !_messages.any((m) => m.id == server.id)) {
      // Realtime echo beat us and the pending row is gone (e.g. list
      // reloaded mid-upload): just append the confirmed message.
      _messages.add(server);
      notifyListeners();
    }
    // If the chat is no longer open, the next loadMessages fetch picks the
    // confirmed row up — never append into another conversation's list.
    loadConversations(silent: true); // ignore: unawaited_futures
  }

  void _failPending(String pendingId) {
    final idx = _messages.indexWhere((m) => m.id == pendingId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].withStatus('failed');
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

  Future<void> updateThemeColor(String conversationId, String? colorHex) async {
    try {
      await MessageService.updateConversationThemeColor(conversationId, colorHex);
      
      // Update local state in conversations list
      for (int i = 0; i < _conversations.length; i++) {
        if (_conversations[i].id == conversationId) {
          _conversations[i] = Conversation(
            id: _conversations[i].id,
            otherUserId: _conversations[i].otherUserId,
            otherUserName: _conversations[i].otherUserName,
            otherUserAvatar: _conversations[i].otherUserAvatar,
            otherUserVerified: _conversations[i].otherUserVerified,
            otherBusinessName: _conversations[i].otherBusinessName,
            lastMessage: _conversations[i].lastMessage,
            lastMessageAt: _conversations[i].lastMessageAt,
            unreadCount: _conversations[i].unreadCount,
            isArchived: _conversations[i].isArchived,
            hiddenAt: _conversations[i].hiddenAt,
            otherUserLastSeen: _conversations[i].otherUserLastSeen,
            themeColor: colorHex,
          );
        }
      }

      // Update local state in archived list
      for (int i = 0; i < _archivedConversations.length; i++) {
        if (_archivedConversations[i].id == conversationId) {
          _archivedConversations[i] = Conversation(
            id: _archivedConversations[i].id,
            otherUserId: _archivedConversations[i].otherUserId,
            otherUserName: _archivedConversations[i].otherUserName,
            otherUserAvatar: _archivedConversations[i].otherUserAvatar,
            otherUserVerified: _archivedConversations[i].otherUserVerified,
            otherBusinessName: _archivedConversations[i].otherBusinessName,
            lastMessage: _archivedConversations[i].lastMessage,
            lastMessageAt: _archivedConversations[i].lastMessageAt,
            unreadCount: _archivedConversations[i].unreadCount,
            isArchived: _archivedConversations[i].isArchived,
            hiddenAt: _archivedConversations[i].hiddenAt,
            otherUserLastSeen: _archivedConversations[i].otherUserLastSeen,
            themeColor: colorHex,
          );
        }
      }

      // Update active conversation
      if (_activeConversation != null && _activeConversation!.id == conversationId) {
        _activeConversation = Conversation(
          id: _activeConversation!.id,
          otherUserId: _activeConversation!.otherUserId,
          otherUserName: _activeConversation!.otherUserName,
          otherUserAvatar: _activeConversation!.otherUserAvatar,
          otherUserVerified: _activeConversation!.otherUserVerified,
          otherBusinessName: _activeConversation!.otherBusinessName,
          lastMessage: _activeConversation!.lastMessage,
          lastMessageAt: _activeConversation!.lastMessageAt,
          unreadCount: _activeConversation!.unreadCount,
          isArchived: _activeConversation!.isArchived,
          hiddenAt: _activeConversation!.hiddenAt,
          otherUserLastSeen: _activeConversation!.otherUserLastSeen,
          themeColor: colorHex,
        );
      }

      // Determine theme name
      String themeName = 'Default Purple';
      switch (colorHex) {
        case '#F97316':
          themeName = 'Orange';
          break;
        case '#10B981':
          themeName = 'Mint';
          break;
        case '#0D9488':
          themeName = 'Teal';
          break;
        case '#0EA5E9':
          themeName = 'Sky Blue';
          break;
        case '#2563EB':
          themeName = 'Royal Blue';
          break;
        case '#8B5CF6':
          themeName = 'Lavender';
          break;
        case '#EC4899':
          themeName = 'Rose Pink';
          break;
        case '#DC2626':
          themeName = 'Crimson';
          break;
        case '#F59E0B':
          themeName = 'Amber Gold';
          break;
        case '#15803D':
          themeName = 'Forest';
          break;
        case '#374151':
          themeName = 'Charcoal';
          break;
      }

      // Show ephemeral theme-change notice in active chat (not a DB message)
      _themeChangeNotice = 'Changed the chat theme to $themeName';
      _themeChangeNoticeTime = DateTime.now();

      // Sync local SQLite conversations cache
      final userId = _currentUserId ?? SupabaseService.auth.currentUser?.id;
      if (userId != null) {
        final all = [..._conversations, ..._archivedConversations];
        await LocalDbService.instance.cacheConversations(userId, all);
      }

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadUnreadNotificationsCount() async {
    try {
      final counts = await NotificationService.getUnreadCounts();
      _unreadNotificationsCount = counts.total;
      _unreadServiceNotificationsCount = counts.services;
      _unreadExploreNotificationsCount = counts.explore;
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
