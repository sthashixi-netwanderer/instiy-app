import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/chat_media_cache_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:giphy_get/giphy_get.dart';
import '../../config/app_theme.dart';
import '../../services/secrets_service.dart';
import '../../services/wallet_lock_service.dart';
import 'recording_helper.dart';
import '../../utils/responsive.dart';
import '../../models/message_model.dart';
import '../../models/picked_media.dart';
import '../../models/chat_background_model.dart';
import '../../providers/providers.dart';
import '../../providers/chat_background_provider.dart';
import '../../widgets/verification_badge.dart';
import '../../providers/message_provider.dart';
import '../../utils/formatters.dart';


import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/skeleton.dart';
import 'report_screen.dart';
import 'archived_chats_screen.dart';
import 'blocked_chats_screen.dart';
import 'chat_user_info_screen.dart';
import 'chat_background_settings_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  bool _isLocked = true;
  bool _checkingLock = true;

  @override
  void initState() {
    super.initState();
    _checkLock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messageProvider).loadConversations();
      ref.read(blockProvider).ensureInitialized();
    });
  }

  Future<void> _checkLock() async {
    final shouldAuth = await WalletLockService.unlockIfNeeded(
      screenKey: 'messages',
      reason: 'Authenticate to view your messages',
    );
    if (!mounted) return;
    if (shouldAuth) {
      setState(() {
        _isLocked = false;
        _checkingLock = false;
      });
      ref.read(messageProvider).loadConversations(); // ignore: unawaited_futures
    } else {
      setState(() {
        _isLocked = true;
        _checkingLock = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgProv = ref.watch(messageProvider);
    final authProv = ref.watch(authProvider);
    final blockProv = ref.watch(blockProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Messages'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(child: Text('Sign in to view your messages')),
      );
    }

    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Messages')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 8),
        ),
      );
    }

    if (_isLocked) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Messages')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: context.rw(80),
                height: context.rh(80),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.lock, size: context.ri(40), color: AppTheme.accent),
              ),
              SizedBox(height: context.rh(16)),
              Text(
                'Messages Locked',
                style: TextStyle(
                  fontSize: context.rsp(20),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(8)),
              Text(
                'Use your fingerprint or screen lock\nto view your messages.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              SizedBox(height: context.rh(24)),
              ShadButton(
                onPressed: () async {
                  final authed = await WalletLockService.authenticate(
                    reason: 'Authenticate to view your messages',
                  );
                  if (authed && mounted) {
                    setState(() => _isLocked = false);
                    ref.read(messageProvider).loadConversations(); // ignore: unawaited_futures
                  }
                },
                leading: Icon(LucideIcons.fingerprint, size: context.ri(20)),
                child: const Text('Unlock Messages'),
              ),
              SizedBox(height: context.rh(12)),
              ShadButton.ghost(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Filter out conversations with blocked users
    final conversations = msgProv.conversations
        .where((c) => !blockProv.isUserBlocked(c.otherUserId))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Messages'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'archived') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()),
                );
              } else if (value == 'blocked') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BlockedChatsScreen()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'archived', child: Text('Archived')),
              PopupMenuItem(value: 'blocked', child: Text('Blocked')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: AdaptiveNav(
        currentIndex: ref.watch(shellTabProvider),
        onTabSelected: (i) => ref.read(shellTabProvider.notifier).state = i,
      ),
      body: RefreshIndicator(
        onRefresh: () => msgProv.loadConversations(),
        child: msgProv.isLoading && conversations.isEmpty
            ? const ListSkeleton(count: 8)
            : conversations.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 8, 100),
                    itemCount: conversations.length + (msgProv.hasMoreConversations ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        const Divider(indent: 76),
                    itemBuilder: (context, index) {
                      if (index == conversations.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          msgProv.loadMoreConversations();
                        });
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final conv = conversations[index];
                      return _ConversationTile(
                        conversation: conv,
                        onTap: () => _openConversation(context, conv, msgProv),
                        onMenuAction: (action) => _handleChatMenuAction(action, conv),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.messageSquare, size: context.ri(64), color: Colors.grey[300]),
          SizedBox(height: context.rh(16)),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Start a conversation with a seller.',
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }

  void _openConversation(BuildContext context, dynamic conv, MessageProvider provider) {
    provider.setActiveConversation(conv);
    provider.loadMessages(conv.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(conversation: conv),
      ),
    );
  }

  void _handleChatMenuAction(String action, dynamic conv) {
    final msgProv = ref.read(messageProvider);
    if (action == 'archive') {
      msgProv.archiveConversation(conv.id);
      ShadToaster.of(context).show(ShadToast(title: const Text('Chat archived')));
    } else if (action == 'unarchive') {
      msgProv.unarchiveConversation(conv.id);
      ShadToaster.of(context).show(ShadToast(title: const Text('Chat unarchived')));
    } else if (action == 'delete') {
      _confirmDeleteChat(conv);
    }
  }

  void _confirmDeleteChat(dynamic conv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat'),
        content: Text('Are you sure you want to delete the chat with ${conv.displayName}? This will hide the conversation from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(messageProvider).hideConversation(conv.id);
              ShadToaster.of(context).show(ShadToast(title: const Text('Chat deleted')));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final dynamic conversation;
  final VoidCallback onTap;
  final void Function(String action)? onMenuAction;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onMenuAction != null
          ? () => _showContextMenu(context)
          : null,
      child: Padding(
        padding: context.rPadding(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            ShadAvatar(
              (conversation.otherUserAvatar != null && conversation.otherUserAvatar!.isNotEmpty)
                  ? conversation.otherUserAvatar!
                  : null,
              size: Size(context.rw(48), context.rh(48)),
              backgroundColor: AppTheme.accent,
              placeholder: Text(
                (conversation.displayName)[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conversation.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.otherUserVerified) ...[
                        const SizedBox(width: 4),
                        VerificationBadge(size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (conversation.lastMessage != null && conversation.lastMessage!.trim().isNotEmpty)
                        ? conversation.lastMessage!
                        : 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: conversation.unreadCount > 0
                          ? AppTheme.charcoalInk
                          : (conversation.lastMessage != null && conversation.lastMessage!.trim().isNotEmpty)
                              ? AppTheme.mutedSteel
                              : AppTheme.mutedSteel.withValues(alpha: 0.5),
                      fontWeight: conversation.unreadCount > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontStyle: (conversation.lastMessage != null && conversation.lastMessage!.trim().isNotEmpty)
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (conversation.lastMessageAt != null)
                  Text(
                    DateFormat('MMM d').format(conversation.lastMessageAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
                  ),
                if (conversation.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  ShadBadge(
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final isArchived = conversation.isArchived == true;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isArchived ? Icons.unarchive : Icons.archive,
                color: isArchived ? Colors.orange : AppTheme.accent,
              ),
              title: Text(isArchived ? 'Unarchive chat' : 'Archive chat'),
              onTap: () {
                Navigator.pop(context);
                onMenuAction?.call(isArchived ? 'unarchive' : 'archive');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete chat'),
              onTap: () {
                Navigator.pop(context);
                onMenuAction?.call('delete');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  final dynamic conversation;

  const ConversationScreen({super.key, required this.conversation});

  @override
  ConsumerState<ConversationScreen> createState() => ConversationScreenState();
}

class ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Map<String, dynamic>? _productReference;
  bool _isSendingMedia = false;
  List<dynamic> _pendingMediaList = [];
  List<bool> _pendingIsVideoList = [];
  // Thumbnails (random video frame) for pending videos, aligned by index
  // with [_pendingMediaList]; null for images or while generating.
  List<Uint8List?> _pendingVideoThumbList = [];
  // Origin of each pending item — 'camera' (in-app capture) or 'gallery' —
  // aligned by index with [_pendingMediaList].
  List<String> _pendingMediaSourceList = [];
  // True while a camera recording is being compressed before it joins the
  // pending strip.
  bool _isProcessingCapture = false;
  String? _firstUnreadMessageId;
  bool _hasSetInitialScroll = false;

  // In-chat keyword search (WhatsApp-style).
  final TextEditingController _chatSearchCtrl = TextEditingController();
  bool _isSearchActive = false;
  List<String> _searchMatchIds = [];
  int _searchMatchIndex = -1;
  bool _showScrollDownButton = false;
  int? _lastMessageCount;
  late final MessageProvider _messageProvider;

  // Selection state
  final Set<String> _selectedMessageIds = {};
  bool _isSelectionMode = false;

  // Reply state
  Message? _replyToMessage;

  // Highlight state (for scroll-to-reply)
  String? _highlightedMessageId;

  // Voice recording state
  bool _isRecording = false;
  bool _isRecordingPaused = false;
  String? _recordPath;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;

  // Chat background state
  ChatBackground? _chatBackground;
  ProviderSubscription<ChatBackgroundProvider>? _chatBackgroundSub;

  final FocusNode _messageFocusNode = FocusNode();

  /// Resolved chat theme colour — reads from the **provider's** live
  /// [activeConversation] so that changes made on the chat-info screen
  /// (which updates the provider and calls notifyListeners) are reflected
  /// instantly without needing to pop/re-push the route.
  Color get _chatColor {
    final live = ref.read(messageProvider).activeConversation;
    final hex = (live != null && live.id == widget.conversation.id)
        ? live.themeColor
        : widget.conversation.themeColor;
    return AppTheme.parseHexColor(hex) ?? AppTheme.accent;
  }

  static const Map<String, List<Color>> _bgGradients = {
    'Sunset': [Color(0xFFFF5F6D), Color(0xFFFFC371)],
    'Ocean': [Color(0xFF2193b0), Color(0xFF6dd5ed)],
    'Lavender': [Color(0xFFe96443), Color(0xFF904e95)],
    'Purple Magic': [Color(0xFF4e54c8), Color(0xFF8f94fb)],
    'Charcoal': [Color(0xFF373B44), Color(0xFF4286f4)],
    'Emerald': [Color(0xFF11998e), Color(0xFF38ef7d)],
  };

  Widget _buildChatBackground() {
    final bg = _chatBackground;
    if (bg == null || bg.backgroundType == 'none') {
      return const SizedBox.shrink();
    }

    Widget bgWidget;
    if (bg.backgroundType == 'gradient' && bg.gradientName != null) {
      final colors = _bgGradients[bg.gradientName!];
      if (colors == null) return const SizedBox.shrink();
      bgWidget = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    } else if (bg.backgroundType == 'image' &&
        (bg.localImagePath != null || bg.imageUrl != null)) {
      // Prefer the locally cached copy; fall back to the R2 URL when the
      // cache is missing (fresh install / cleared app data).
      final useLocal = !kIsWeb &&
          bg.localImagePath != null &&
          File(bg.localImagePath!).existsSync();
      if (!useLocal && bg.imageUrl == null) {
        return const SizedBox.shrink();
      }
      bgWidget = useLocal
          ? Image.file(
              File(bg.localImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : CachedNetworkImage(
              imageUrl: bg.imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            );
    } else {
      return const SizedBox.shrink();
    }

    if (bg.blurIntensity > 0) {
      return ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: bg.blurIntensity,
          sigmaY: bg.blurIntensity,
        ),
        child: bgWidget,
      );
    }

    return bgWidget;
  }

  @override
  void initState() {
    super.initState();
    _messageProvider = ref.read(messageProvider);
    _productReference = _messageProvider.pendingProductReference;
    if (_productReference != null) {
      _messageProvider.consumePendingProductReference();
    }
    _messageCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _scrollCtrl.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChatBackground());
    // React to background changes made on the settings screen (which updates
    // the shared provider and calls notifyListeners) so the new image shows
    // immediately without popping back / re-entering the chat.
    _chatBackgroundSub = ref.listenManual<ChatBackgroundProvider>(
      chatBackgroundProvider,
      (_, _) => _adoptProviderBackground(),
    );
  }

  Future<void> _loadChatBackground() async {
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    final bgProv = ref.read(chatBackgroundProvider);
    await bgProv.loadBackground(userId, widget.conversation.id);
    if (mounted) {
      setState(() {
        _chatBackground = bgProv.background;
      });
    }
  }

  /// Adopts the shared provider's background into local render state when a
  /// save happens while this chat is open. Only backgrounds scoped to this
  /// conversation — or globals when this chat itself resolved to the global
  /// fallback — are applied, so a background saved for another chat can't
  /// leak in through the shared single-slot provider.
  void _adoptProviderBackground() {
    final bg = ref.read(chatBackgroundProvider).background;
    if (bg == null || !mounted) return;
    final appliesHere = bg.conversationId == widget.conversation.id ||
        (bg.conversationId == null &&
            _chatBackground?.conversationId == null);
    if (!appliesHere) return;
    setState(() => _chatBackground = bg);
  }

  void _scrollListener() {
    _updateScrollButtonVisibility();

    // Load older messages when scrolled near the top
    if (_scrollCtrl.offset < 200) {
      final msgProv = ref.read(messageProvider);
      if (!msgProv.isLoadingMoreMessages && msgProv.hasMoreMessages) {
        // Older pages are prepended at the top; a plain (non-reversed) list
        // keeps the same pixel offset, which visually leaps the viewport up
        // to the freshly loaded older messages. Anchor the view by shifting
        // the offset by the height of everything that was inserted above.
        final anchorOffset = _scrollCtrl.offset;
        final oldCount = msgProv.messages.length;
        msgProv.loadMoreMessages(widget.conversation.id).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollCtrl.hasClients) return;
            final added = msgProv.messages.length - oldCount;
            if (added <= 0) return;
            var insertedHeight = 0.0;
            for (var i = 0; i < added; i++) {
              insertedHeight += _estimateMessageHeight(msgProv.messages[i]);
            }
            _scrollCtrl.jumpTo(
              (anchorOffset + insertedHeight).clamp(
                0.0,
                _scrollCtrl.position.maxScrollExtent,
              ),
            );
          });
        });
      }
    }
  }

  /// Shows the jump-to-newest button whenever the user is scrolled away
  /// from the bottom of the chat (WhatsApp-style: even a partial screen of
  /// scroll is enough).
  void _updateScrollButtonVisibility() {
    if (!_scrollCtrl.hasClients) return;
    final show = _scrollCtrl.offset < _scrollCtrl.position.maxScrollExtent - 120;
    if (show != _showScrollDownButton) {
      setState(() {
        _showScrollDownButton = show;
      });
    }
  }

  @override
  void dispose() {
    _chatBackgroundSub?.close();
    _chatSearchCtrl.dispose();
    _messageCtrl.dispose();
    _captionCtrl.dispose();
    _scrollCtrl.dispose();
    _messageFocusNode.dispose();
    _messageProvider.disposeConversation();
    _recordTimer?.cancel();
    RecordingHelper.dispose();
    super.dispose();
  }

  Future<Uint8List?> _readFileBytes(String path) => RecordingHelper.readFileBytes(path);

  // Helper to calculate bottom padding for ListView
  double _listBottomPadding() => 16;

  // WhatsApp-style presence label under the user's name in the chat header.
  String _presenceLabel() {
    if (widget.conversation.isOnline) return 'online';
    final lastSeen = widget.conversation.otherUserLastSeen?.toLocal();
    if (lastSeen == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    final time = DateFormat('h:mm a').format(lastSeen);
    final days = today.difference(day).inDays;
    if (days == 0) return 'last seen today at $time';
    if (days == 1) return 'last seen yesterday at $time';
    return 'last seen ${DateFormat('d/M/yyyy').format(lastSeen)} at $time';
  }

  void _removeReference() {
    setState(() {
      _productReference = null;
    });
  }

  void _handleMenuAction(String action, String otherUserId, bool isBlocked) {
    switch (action) {
      case 'search':
        _startChatSearch();
        break;
      case 'block':
        _showBlockConfirmation(otherUserId);
        break;
      case 'unblock':
        _unblockUser(otherUserId);
        break;
      case 'report':
        _openReportScreen(otherUserId);
        break;
      case 'chat_background':
        _openChatBackgroundSettings();
        break;
    }
  }

  void _showBlockConfirmation(String userId) {
    final name = widget.conversation.displayName;
    AppTheme.showGlassDialog(
      context: context,
      title: Text('Block $name?'),
      description: Text(
        '$name won\'t be able to send you messages. You can unblock them later from this chat.',
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton.destructive(
          onPressed: () {
            Navigator.of(context).pop();
            ref.read(blockProvider).blockUser(userId);
            if (mounted) {
              ShadToaster.of(context).show(
                ShadToast(
                  title: Text('$name blocked'),
                  description: const Text('They can no longer send you messages.'),
                ),
              );
            }
          },
          child: const Text('Block'),
        ),
      ],
    );
  }

  void _unblockUser(String userId) {
    ref.read(blockProvider).unblockUser(userId);
    final name = widget.conversation.displayName;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text('$name unblocked'),
        description: const Text('They can now send you messages again.'),
      ),
    );
  }

  void _openReportScreen(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          reportedUserId: userId,
          reportedUserName: widget.conversation.displayName,
          conversationId: widget.conversation.id,
        ),
      ),
    );
  }

  void _openChatBackgroundSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatBackgroundSettingsScreen(
          conversationId: widget.conversation.id,
        ),
      ),
    );
    // Reload background when returning from settings
    if (mounted) {
      unawaited(_loadChatBackground());
    }
  }

  // ── Selection ──

  void _enterSelectionMode(String messageId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedMessageIds.add(messageId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _showDeleteSheet() {
    final uid = ref.read(authProvider).user?.id;
    final selectedMessages = _messageProvider.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    final allOwnMessages = selectedMessages.every((m) => m.senderId == uid);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.whisperBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete ${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: AppTheme.charcoalInk),
              title: const Text('Delete for me'),
              subtitle: const Text('Messages will only be hidden from you'),
              onTap: () {
                Navigator.pop(ctx);
                _messageProvider.deleteMessagesForMe(_selectedMessageIds.toList());
                _exitSelectionMode();
              },
            ),
            if (allOwnMessages)
              ListTile(
                leading: const Icon(LucideIcons.trash, color: Colors.red),
                title: const Text('Delete for everyone'),
                subtitle: const Text('Messages will be permanently removed'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteForEveryone(selectedMessages);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteForEveryone(List<Message> messages) {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Delete for everyone?'),
      description: Text(
        'This will permanently delete ${messages.length} message${messages.length > 1 ? 's' : ''} for both you and ${widget.conversation.displayName}. This cannot be undone.',
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton.destructive(
          onPressed: () {
            Navigator.of(context).pop();
            _messageProvider.deleteMessagesForEveryone(_selectedMessageIds.toList());
            _exitSelectionMode();
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }

  // ── Reply ──

  void _setReplyTo(Message message) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyToMessage = message;
    });
    // Focus the text field
    FocusScope.of(context).requestFocus();
  }

  void _clearReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  /// Rough per-bubble height estimate used to land near a target message
  /// when jumping/scrolling to it. Exact pixel positions aren't available
  /// without building the widgets, so this heuristic gets the viewport close
  /// enough that the highlight + divider are visible.
  double _estimateMessageHeight(Message m) {
    double h = 40; // bubble padding + timestamp row
    if (m.mediaType == 'image' || m.mediaType == 'video') {
      h += 220;
    } else if (m.mediaType == 'audio') {
      h += 64;
    }
    if (m.isReply) h += 44;
    if (m.productReference != null) h += 64;
    final text = m.content.trim();
    if (text.isNotEmpty) {
      h += (text.length / 36).ceil().clamp(1, 15) * 18;
    }
    return h + 8; // spacing between bubbles
  }

  double _estimatedOffsetBefore(int index) {
    final messages = _messageProvider.messages;
    var offset = 0.0;
    for (var i = 0; i < index && i < messages.length; i++) {
      offset += _estimateMessageHeight(messages[i]);
    }
    return offset;
  }

  void _scrollToMessage(String messageId, {bool jump = false}) {
    final messages = _messageProvider.messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    // Using Future.delayed to ensure the ScrollController has registered clients and correct scroll extent
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final targetOffset = _estimatedOffsetBefore(index).clamp(
        0.0,
        _scrollCtrl.position.maxScrollExtent,
      );

      if (jump) {
        _scrollCtrl.jumpTo(targetOffset);
      } else {
        _scrollCtrl.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Highlight the message
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  /// Positions the chat at the latest message (bottom, by the input area).
  /// The first unread incoming message is still marked with a divider, but
  /// it is not a scroll target — jumping up to it (with estimated offsets)
  /// regularly landed the view on older history.
  Future<void> _setInitialScrollPosition() async {
    final userId = ref.read(authProvider).user?.id;
    bool isUnread(Message m) => m.senderId != userId && !m.isRead;

    if (!mounted) return;
    final unreadIndex = _messageProvider.messages.indexWhere(isUnread);

    // Wait for the items to lay out before jumping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (unreadIndex != -1) {
        setState(
            () => _firstUnreadMessageId = _messageProvider.messages[unreadIndex].id);
      }
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      _settleOnBottom();
    });
  }

  /// Images/voice notes keep growing the list extent after the first jump to
  /// the bottom. Re-settle until the extent stabilizes so the chat truly
  /// opens on the latest message — but stop as soon as the user scrolls up
  /// on their own, so they are never yanked around.
  void _settleOnBottom() {
    var lastBottom = double.negativeInfinity;
    for (final delay in const [200, 500, 900, 1400]) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final pos = _scrollCtrl.position;
        // The user moved away from the bottom on their own — leave them be.
        if (pos.pixels < lastBottom - 8) return;
        lastBottom = pos.maxScrollExtent;
        if (pos.pixels != pos.maxScrollExtent) {
          _scrollCtrl.jumpTo(pos.maxScrollExtent);
        }
      });
    }
  }

  // ─── In-chat search (WhatsApp-style) ─────────────────────────────

  void _startChatSearch() {
    setState(() {
      _isSearchActive = true;
      _searchMatchIds = [];
      _searchMatchIndex = -1;
    });
  }

  void _closeChatSearch() {
    _chatSearchCtrl.clear();
    setState(() {
      _isSearchActive = false;
      _searchMatchIds = [];
      _searchMatchIndex = -1;
    });
  }

  void _runChatSearch(String query) {
    final q = query.trim().toLowerCase();
    final matches = q.isEmpty
        ? <String>[]
        : _messageProvider.messages
            .where((m) => m.content.toLowerCase().contains(q))
            .map((m) => m.id)
            .toList();
    setState(() {
      _searchMatchIds = matches;
      // Start at the most recent match, like WhatsApp.
      _searchMatchIndex = matches.isEmpty ? -1 : matches.length - 1;
    });
    if (_searchMatchIndex != -1) {
      _scrollToMessage(_searchMatchIds[_searchMatchIndex]);
    }
  }

  void _stepSearchMatch(int delta) {
    if (_searchMatchIds.isEmpty || _searchMatchIndex == -1) return;
    final next = (_searchMatchIndex + delta).clamp(0, _searchMatchIds.length - 1);
    if (next == _searchMatchIndex) return;
    setState(() => _searchMatchIndex = next);
    _scrollToMessage(_searchMatchIds[next]);
  }

  PreferredSizeWidget _buildChatSearchAppBar(BuildContext context) {
    return AppTheme.glassAppBar(
      context: context,
      title: ShadInput(
        controller: _chatSearchCtrl,
        placeholder: const Text('Search messages'),
        autofocus: true,
        keyboardType: TextInputType.text,
        style: const TextStyle(fontSize: 14),
        onChanged: _runChatSearch,
      ),
      actions: [
        if (_searchMatchIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                '${_searchMatchIndex + 1}/${_searchMatchIds.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mutedSteel),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(LucideIcons.chevronUp, size: 20),
          onPressed: _searchMatchIds.isEmpty ? null : () => _stepSearchMatch(-1),
        ),
        IconButton(
          icon: const Icon(LucideIcons.chevronDown, size: 20),
          onPressed: _searchMatchIds.isEmpty ? null : () => _stepSearchMatch(1),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: _closeChatSearch,
        ),
      ],
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    final hasRef = _productReference != null;
    final hasMedia = _pendingMediaList.isNotEmpty;
    final replyId = _replyToMessage?.id;
    final refToSend = _productReference;

    if (text.isEmpty && !hasRef && !hasMedia) return;

    // If there's pending media, send them consecutively
    if (hasMedia) {
      for (int i = 0; i < _pendingMediaList.length; i++) {
        _sendMediaFireAndForget(
          file: _pendingMediaList[i],
          mediaType: _pendingIsVideoList[i] ? 'video' : 'image',
          caption: i == 0 ? text : '',
          replyToMessageId: replyId,
          thumbnailBytes: i < _pendingVideoThumbList.length
              ? _pendingVideoThumbList[i]
              : null,
          mediaSource: i < _pendingMediaSourceList.length
              ? _pendingMediaSourceList[i]
              : null,
        );
      }
      _messageCtrl.clear();
      setState(() {
        _pendingMediaList = [];
        _pendingIsVideoList = [];
        _pendingVideoThumbList = [];
        _pendingMediaSourceList = [];
        _productReference = null;
        _replyToMessage = null;
      });
      return;
    }

    _messageCtrl.clear();
    setState(() {
      _productReference = null;
      _replyToMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      await ref.read(messageProvider).sendMessage(
        text,
        productReference: refToSend,
        replyToMessageId: replyId,
      );
    } catch (_) {}
  }

  /// WhatsApp-style jump back to the newest messages. Long distances
  /// (deep in old history) animate faster per pixel so the button always
  /// feels like a quick fling to the bottom, never a slow crawl.
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      final distance = pos.maxScrollExtent - pos.pixels;
      if (distance <= 0) {
        _updateScrollButtonVisibility();
        return;
      }
      final duration = Duration(
        milliseconds:
            (distance / pos.viewportDimension * 140 + 180)
                .clamp(220, 450)
                .round(),
      );
      _scrollCtrl
          .animateTo(
            pos.maxScrollExtent,
            duration: duration,
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) _updateScrollButtonVisibility();
          });
    });
  }

  Future<void> _pickMedia() async {
    final source = await _showMediaSourceSheet();
    if (source == null) return;

    if (source == 'gif') {
      unawaited(_openGifPicker());
      return;
    }

    final picker = ImagePicker();

    try {
      switch (source) {
        case 'camera_image':
          final picked = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1080,
            maxHeight: 1080,
            imageQuality: 60,
          );
          if (picked == null) return;
          final bytes = await picked.readAsBytes();
          await _handleImagePicked(bytes, picked.name, mediaSource: 'camera');
        case 'camera_video':
          final picked = await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 60),
          );
          if (picked == null) return;
          final processed = await _prepareRecordedVideo(picked);
          await _handleVideoPicked(
            processed.bytes,
            processed.name,
            path: processed.path,
            mediaSource: 'camera',
          );
        case 'video':
          final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
          if (picked == null) return;
          final bytes = await picked.readAsBytes();
          await _handleVideoPicked(bytes, picked.name, path: picked.path, mediaSource: 'gallery');
        default:
          final pickedList = await picker.pickMultiImage(maxWidth: 1080, maxHeight: 1080, imageQuality: 60);
          if (pickedList.isEmpty) return;
          for (final picked in pickedList) {
            final bytes = await picked.readAsBytes();
            await _handleImagePicked(bytes, picked.name, mediaSource: 'gallery');
          }
      }
    } catch (e) {
      // Camera capture can fail when permission is denied or unavailable.
      debugPrint('Media capture failed: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Could not capture media. Check camera permissions.')),
        );
      }
    }
  }

  /// Shrinks a camera recording before it joins the pending strip — raw
  /// camera output is far too large to upload uncompressed. Falls back to
  /// the original bytes when compression isn't possible (web, failure).
  Future<PickedMedia> _prepareRecordedVideo(XFile picked) async {
    final original = await PickedMedia.fromXFile(picked);
    setState(() => _isProcessingCapture = true);
    try {
      final compressed = await VideoService.compressVideo(original, maxDurationSeconds: null);
      return compressed ?? original;
    } catch (_) {
      return original;
    } finally {
      if (mounted) setState(() => _isProcessingCapture = false);
    }
  }

  Future<void> _handleImagePicked(dynamic bytes, String name, {String mediaSource = 'gallery'}) async {
    setState(() {
      _pendingMediaList.add(bytes);
      _pendingIsVideoList.add(false);
      _pendingVideoThumbList.add(null);
      _pendingMediaSourceList.add(mediaSource);
    });
  }

  Future<void> _handleVideoPicked(dynamic bytes, String name, {String? path, String mediaSource = 'gallery'}) async {
    // Add the video bytes — backend handles duration check and trimming.
    // A thumbnail from a random frame is generated in the background and
    // attached so the chat bubble shows a preview instead of an icon.
    final slot = _pendingMediaList.length;
    setState(() {
      _pendingMediaList.add(bytes);
      _pendingIsVideoList.add(true);
      _pendingVideoThumbList.add(null);
      _pendingMediaSourceList.add(mediaSource);
    });

    final thumb = await VideoService.generateThumbnail(path);
    if (thumb != null && mounted) {
      setState(() {
        if (slot < _pendingVideoThumbList.length && _pendingIsVideoList[slot]) {
          _pendingVideoThumbList[slot] = thumb;
        }
      });
    }
  }

  void clearPendingMedia() {
    setState(() {
      _pendingMediaList.clear();
      _pendingIsVideoList.clear();
      _pendingVideoThumbList.clear();
      _pendingMediaSourceList.clear();
    });
  }

  Future<void> _openGifPicker() async {
    // Dismiss system keyboard
    FocusScope.of(context).unfocus();
    try {
      final gif = await GiphyGet.getGif(
        context: context,
        apiKey: SecretsService.instance.giphyApiKey,
        showGIFs: true,
        showStickers: true,
        showEmojis: true,
        tabColor: AppTheme.accent,
      );
      if (gif != null) {
        final url = gif.images?.original?.url ??
            gif.images?.fixedHeight?.url ??
            gif.images?.downsized?.url;
        if (url != null) {
          await _sendDirectMedia(url, 'gif');
        }
      }
    } catch (e) {
      debugPrint('Error opening GIF picker: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Could not open GIF picker: $e')),
        );
      }
    }
  }

  Future<void> _sendDirectMedia(String url, String type) async {
    try {
      await ref.read(messageProvider).sendMediaMessage(
        mediaUrl: url,
        mediaType: type,
        caption: '',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (_) {}
  }

  void _sendMediaFireAndForget({
    required dynamic file,
    required String mediaType,
    required String caption,
    String? replyToMessageId,
    Uint8List? thumbnailBytes,
    String? mediaSource,
  }) {
    setState(() => _isSendingMedia = true);

    // Clear input immediately so user can type next message
    _messageCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    () async {
      try {
        final folder = 'chat-media/${mediaType == 'video' ? 'videos' : 'images'}';
        final ext = mediaType == 'video' ? 'mp4' : 'jpg';
        final rawBytes = file is List<int> ? file : await _readFileBytes('$file');
        final bytes = rawBytes is Uint8List ? rawBytes : (rawBytes != null ? Uint8List.fromList(rawBytes) : null);
        if (bytes == null) throw Exception('Could not read media file');
        final url = await StorageService.uploadImageBytes(
          bytes: bytes,
          folder: folder,
          extension: ext,
        );

        // Videos carry their thumbnail in the media URL ("videoUrl|thumbUrl")
        // so the chat bubble can show a preview frame without loading the video.
        var mediaUrl = url;
        if (mediaType == 'video' && thumbnailBytes != null) {
          try {
            final thumbUrl = await StorageService.uploadImageBytes(
              bytes: thumbnailBytes,
              folder: 'chat-media/thumbnails',
              extension: 'jpg',
            );
            mediaUrl = '$url|$thumbUrl';
          } catch (_) {
            // Thumbnail is optional — send the video without it.
          }
        }

        if (mounted) {
          await ref.read(messageProvider).sendMediaMessage(
            mediaUrl: mediaUrl,
            mediaType: mediaType,
            caption: caption,
            replyToMessageId: replyToMessageId,
            mediaSource: mediaSource,
          );
        }
      } catch (_) {
        // Silently fail - could show a snackbar if needed
      } finally {
        if (mounted) {
          setState(() => _isSendingMedia = false);
        }
      }
    }();
  }

  Widget _buildPendingMediaThumbnail(dynamic media, bool isVideo, Uint8List? videoThumb) {
    if (isVideo) {
      return Container(
        width: 70,
        height: 70,
        color: AppTheme.charcoalInk,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (videoThumb != null)
              Positioned.fill(
                child: Image.memory(
                  videoThumb,
                  fit: BoxFit.cover,
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(LucideIcons.play, size: 16, color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (media is Uint8List) {
      return Image.memory(
        media,
        width: 70,
        height: 70,
        fit: BoxFit.cover,
      );
    } else if (media is List<int>) {
      return Image.memory(
        Uint8List.fromList(media),
        width: 70,
        height: 70,
        fit: BoxFit.cover,
      );
    } else if (media is File) {
      return Image.file(
        media,
        width: 70,
        height: 70,
        fit: BoxFit.cover,
      );
    } else if (media is String) {
      return Image.file(
        File(media),
        width: 70,
        height: 70,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: 70,
      height: 70,
      color: AppTheme.warmMist,
      child: const Icon(LucideIcons.image, size: 20, color: AppTheme.mutedSteel),
    );
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Voice recording is not available on web.')),
        );
      }
      return;
    }
    try {
      final hasPermission = await RecordingHelper.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Microphone permission is required to record voice notes.')),
          );
        }
        return;
      }

      final path = await RecordingHelper.startRecording();

      setState(() {
        _isRecording = true;
        _isRecordingPaused = false;
        _recordPath = path;
        _recordDurationSeconds = 0;
      });

      _startRecordDurationTimer();
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Could not start recording: $e')),
        );
      }
    }
  }

  /// Ticks the visible recording duration once per second while active.
  void _startRecordDurationTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordDurationSeconds++;
        });
      }
    });
  }

  /// Pauses the in-progress voice note. The mic session stays open and the
  /// file keeps everything recorded so far — [ _resumeRecording] continues
  /// the same take.
  Future<void> _pauseRecording() async {
    try {
      await RecordingHelper.pauseRecording();
      _recordTimer?.cancel(); // Freeze the duration counter while paused.
      if (mounted) setState(() => _isRecordingPaused = true);
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  /// Resumes the paused voice note — same session, same file.
  Future<void> _resumeRecording() async {
    try {
      await RecordingHelper.resumeRecording();
      if (!mounted) return;
      setState(() => _isRecordingPaused = false);
      _startRecordDurationTimer();
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordTimer?.cancel();
      await RecordingHelper.stopRecording();
      if (_recordPath != null) {
        await RecordingHelper.deleteFile(_recordPath!);
      }
      setState(() {
        _isRecording = false;
        _isRecordingPaused = false;
        _recordPath = null;
        _recordDurationSeconds = 0;
      });
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    try {
      _recordTimer?.cancel();
      // Safe to call from a paused state too — stop() finalizes the file
      // with only the audio captured before the pause.
      final path = await RecordingHelper.stopRecording();
      setState(() {
        _isRecording = false;
        _isRecordingPaused = false;
      });

      if (path == null) return;
      if (!await RecordingHelper.fileExists(path)) return;

      final tempDir = await RecordingHelper.getTempDir();
      final localCopyPath = '$tempDir/local_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await RecordingHelper.copyFile(path, localCopyPath);

      _sendVoiceNoteFireAndForget(localCopyPath, path);
    } catch (e) {
      debugPrint('Error stopping and sending recording: $e');
    }
  }

  void _sendVoiceNoteFireAndForget(String localPath, String tempPath) {
    setState(() => _isSendingMedia = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    () async {
      try {
        final folder = 'chat-media/audio';
        // Read bytes from the temp file and upload via bytes.
        final tempFile = await _readFileBytes(tempPath);
        if (tempFile == null) throw Exception('Could not read recording file');
        final url = await StorageService.uploadImageBytes(
          bytes: tempFile,
          folder: folder,
          extension: 'm4a',
        );

        // Keep the recording on the sender's device (same file name the
        // voice bubble derives from the URL) so it plays offline instantly
        // and never needs to round-trip through R2.
        try {
          final docsDir = await RecordingHelper.getDocsDir();
          final voiceDir = '$docsDir/voice_notes';
          final localName = Uri.parse(url).pathSegments.last;
          await RecordingHelper.copyFile(localPath, '$voiceDir/$localName');
        } catch (e) {
          debugPrint('Error persisting sent voice note locally: $e');
        }

        try {
          await RecordingHelper.deleteFile(localPath);
          await RecordingHelper.deleteFile(tempPath);
        } catch (_) {}

        if (mounted) {
          await ref.read(messageProvider).sendMediaMessage(
            mediaUrl: url,
            mediaType: 'voice',
            caption: '',
            replyToMessageId: _replyToMessage?.id,
          );
          setState(() {
            _replyToMessage = null;
          });
        }
      } catch (e) {
        debugPrint('Error uploading/sending voice note: $e');
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast(title: Text('Failed to upload voice note: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSendingMedia = false);
        }
      }
    }();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<String?> _showMediaSourceSheet() {
    return showShadSheet<String>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Send Media'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _MediaOption(
              icon: LucideIcons.camera,
              iconColor: _chatColor,
              iconBgColor: _chatColor.withValues(alpha: 0.1),
              title: 'Take Photo',
              subtitle: 'Capture a photo with your camera',
              onTap: () => Navigator.of(ctx).pop('camera_image'),
            ),
            const SizedBox(height: 8),
            _MediaOption(
              icon: LucideIcons.video,
              iconColor: _chatColor,
              iconBgColor: _chatColor.withValues(alpha: 0.1),
              title: 'Record Video',
              subtitle: 'Record with your camera (max 60s)',
              onTap: () => Navigator.of(ctx).pop('camera_video'),
            ),
            const SizedBox(height: 8),
            _MediaOption(
              icon: LucideIcons.image,
              iconColor: _chatColor,
              iconBgColor: _chatColor.withValues(alpha: 0.1),
              title: 'Gallery Photo',
              subtitle: 'Send photos from your gallery',
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            const SizedBox(height: 8),
            _MediaOption(
              icon: LucideIcons.film,
              iconColor: _chatColor,
              iconBgColor: _chatColor.withValues(alpha: 0.1),
              title: 'Gallery Video',
              subtitle: 'Send a video from your gallery (max 60s)',
              onTap: () => Navigator.of(ctx).pop('video'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgProv = ref.watch(messageProvider);
    final userId = ref.read(authProvider).user?.id;

    // Set initial scroll position when messages are first loaded. Gate on
    // isLoadingMessages (NOT isLoading — that tracks the conversations list)
    // so the jump targets the network list rather than the cache-first
    // snapshot that gets replaced a moment later.
    if (!msgProv.isLoadingMessages &&
        msgProv.messages.isNotEmpty &&
        !_hasSetInitialScroll) {
      _hasSetInitialScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setInitialScrollPosition();
      });
    }

    // The list's extent can change without a scroll event (older messages
    // paginated in, messages deleted) — re-evaluate the jump-to-bottom
    // button once the frame settles.
    if (_lastMessageCount != msgProv.messages.length) {
      _lastMessageCount = msgProv.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateScrollButtonVisibility();
      });
    }

    final blockProv = ref.watch(blockProvider);
    final otherUserId = widget.conversation.otherUserId;
    final isBlocked = blockProv.isUserBlocked(otherUserId);
    final presenceLabel = _presenceLabel();

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: _isSelectionMode
          ? AppTheme.glassAppBar(
              context: context,
              leading: IconButton(
                icon: const Icon(LucideIcons.x, size: 22),
                onPressed: _exitSelectionMode,
              ),
              title: Text('${_selectedMessageIds.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 20, color: Colors.red),
                  onPressed: _showDeleteSheet,
                ),
              ],
            )
          : _isSearchActive
              ? _buildChatSearchAppBar(context)
              : AppTheme.glassAppBar(
              context: context,
              title: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatUserInfoScreen(
                        conversation: widget.conversation,
                      ),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShadAvatar(
                      widget.conversation.otherUserAvatar,
                      size: const Size(36, 36),
                      backgroundColor: AppTheme.accent,
                      placeholder: Text(
                        widget.conversation.displayName.isNotEmpty
                            ? widget.conversation.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: context.rw(10)),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.conversation.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.conversation.otherUserVerified) ...[
                                const SizedBox(width: 4),
                                VerificationBadge(size: 14),
                              ],
                            ],
                          ),
                          if (presenceLabel.isNotEmpty)
                            Text(
                              presenceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: AppTheme.mutedSteel,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Call',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  icon: const Icon(LucideIcons.phone, size: 20),
                  enabled: !isBlocked,
                  onSelected: (value) {
                    final isVideo = value == 'video';
                    ref.read(callProvider.notifier).startCall(
                          peerId: otherUserId,
                          peerName: widget.conversation.displayName,
                          peerAvatar: widget.conversation.otherUserAvatar,
                          video: isVideo,
                        );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'voice',
                      child: Row(
                        children: [
                          Icon(LucideIcons.phone, size: 18, color: AppTheme.accent),
                          SizedBox(width: 10),
                          Text('Voice call'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'video',
                      child: Row(
                        children: [
                          Icon(LucideIcons.video, size: 18, color: AppTheme.accent),
                          SizedBox(width: 10),
                          Text('Video call'),
                        ],
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  icon: const Icon(LucideIcons.ellipsis, size: 20),
                  onSelected: (value) => _handleMenuAction(value, otherUserId, isBlocked),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'search',
                      child: Row(
                        children: [
                          Icon(LucideIcons.search, size: 18, color: AppTheme.mutedSteel),
                          SizedBox(width: 10),
                          Text('Search Messages'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'chat_background',
                      child: Row(
                        children: [
                          Icon(LucideIcons.image, size: 18, color: AppTheme.mutedSteel),
                          SizedBox(width: 10),
                          Text('Chat Background'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: isBlocked ? 'unblock' : 'block',
                      child: Row(
                        children: [
                          Icon(
                            isBlocked ? LucideIcons.shieldCheck : LucideIcons.shield,
                            size: 18,
                            color: isBlocked ? AppTheme.accent : Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isBlocked ? 'Unblock User' : 'Block User',
                            style: TextStyle(color: isBlocked ? null : Colors.red),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(LucideIcons.flag, size: 18, color: AppTheme.mutedSteel),
                          SizedBox(width: 10),
                          Text('Report User'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Stack(
        children: [
          // Full-bleed Chat background layer
          Positioned.fill(
            child: _buildChatBackground(),
          ),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      msgProv.isLoading && msgProv.messages.isEmpty
                          ? Positioned.fill(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MessageBubbleSkeleton(isMe: false),
                                      const SizedBox(height: 8),
                                      MessageBubbleSkeleton(isMe: true),
                                      const SizedBox(height: 8),
                                      MessageBubbleSkeleton(isMe: false),
                                      const SizedBox(height: 8),
                                      MessageBubbleSkeleton(isMe: true),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : msgProv.messages.isEmpty
                              ? const Center(
                                  child: Text('Start a conversation',
                                      style: TextStyle(color: AppTheme.mutedSteel)),
                                )
                              : Column(
                                  children: [
                                    if (msgProv.themeChangeNotice != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                        child: Row(
                                          children: [
                                            Expanded(child: Divider(color: AppTheme.whisperBorder, thickness: 1)),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _chatColor.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(LucideIcons.palette, size: 12, color: _chatColor),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    msgProv.themeChangeNotice!,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: _chatColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(child: Divider(color: AppTheme.whisperBorder, thickness: 1)),
                                          ],
                                        ),
                                      ),
                                    Expanded(
                                      child: Builder(builder: (context) {
                                        // All media in this conversation
                                        // (oldest → newest), so the viewer
                                        // can swipe through them like
                                        // WhatsApp. Built once per list
                                        // rebuild, not per bubble.
                                        final mediaUrls = <String>[];
                                        final mediaThumbs = <String?>[];
                                        final mediaIndexById = <String, int>{};
                                        for (final m in msgProv.messages) {
                                          final url = m.mediaUrl;
                                          if (url == null || url.isEmpty) continue;
                                          mediaIndexById[m.id] = mediaUrls.length;
                                          mediaUrls.add(url);
                                          mediaThumbs.add(m.thumbnailUrl);
                                        }
                                        return ListView.builder(
                                        // Attaching the controller is what
                                        // brings the initial jump-to-latest,
                                        // the jump-to-bottom button, reply
                                        // jumps and top-pagination to life —
                                        // every one of them no-ops without it.
                                        controller: _scrollCtrl,
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
                                          16,
                                          _listBottomPadding(),
                                        ),
                                        itemCount: msgProv.messages.length + (msgProv.hasMoreMessages ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index == 0 && msgProv.hasMoreMessages) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                              ),
                                            );
                                          }
                                          final msgIndex = msgProv.hasMoreMessages ? index - 1 : index;
                                          final msg = msgProv.messages[msgIndex];
                                          final isMe = msg.senderId == userId;
                                          final isFirstUnread = _firstUnreadMessageId == msg.id;

                                          final child = _MessageBubble(
                                            message: msg,
                                            isMe: isMe,
                                            isSelected: _selectedMessageIds.contains(msg.id),
                                            isSelectionMode: _isSelectionMode,
                                            isHighlighted: _highlightedMessageId == msg.id,
                                            chatColor: _chatColor,
                                            conversationMediaUrls: mediaUrls,
                                            conversationMediaThumbnails: mediaThumbs,
                                            conversationMediaIndex: mediaIndexById[msg.id] ?? 0,
                                            onLongPress: () => isMe ? _enterSelectionMode(msg.id) : null,
                                            onTap: () {
                                              if (_isSelectionMode && isMe) {
                                                _toggleSelection(msg.id);
                                              }
                                            },
                                            onSwipeReply: () => _setReplyTo(msg),
                                            onReplyTap: msg.isReply ? () => _scrollToMessage(msg.replyToMessageId!) : null,
                                            onCallback: (isVideo) {
                                              if (isBlocked) return;
                                              ref.read(callProvider.notifier).startCall(
                                                peerId: otherUserId,
                                                peerName: widget.conversation.displayName,
                                                peerAvatar: widget.conversation.otherUserAvatar,
                                                video: isVideo,
                                              );
                                            },
                                          );

                                          if (isFirstUnread) {
                                            return Column(
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                                  child: Row(
                                                    children: [
                                                      const Expanded(child: Divider(color: AppTheme.whisperBorder, thickness: 1)),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: _chatColor.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Text(
                                                          'Unread Messages',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: _chatColor,
                                                          ),
                                                        ),
                                                      ),
                                                      const Expanded(child: Divider(color: AppTheme.whisperBorder, thickness: 1)),
                                                    ],
                                                  ),
                                                ),
                                                child,
                                              ],
                                            );
                                          }
                                          return child;
                                        },
                                      );
                                      }),
                                    ),
                                  ],
                                ),
                      // Jump-to-bottom button (WhatsApp-style). Always in
                      // the tree so it fades in/out smoothly; IgnorePointer
                      // keeps the hidden state from swallowing taps.
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: IgnorePointer(
                          ignoring: !_showScrollDownButton,
                          child: AnimatedOpacity(
                            opacity: _showScrollDownButton ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: FloatingActionButton.small(
                              backgroundColor: AppTheme.pureSurface,
                              foregroundColor: AppTheme.charcoalInk,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: AppTheme.whisperBorder),
                              ),
                              onPressed: _scrollToBottom,
                              child: const Icon(LucideIcons.chevronDown, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_replyToMessage != null)
                  _ReplyPreviewCard(
                    message: _replyToMessage!,
                    currentUserId: userId ?? '',
                    otherUserName: widget.conversation.otherUserName ?? '',
                    otherUserVerified: widget.conversation.otherUserVerified,
                    otherBusinessName: widget.conversation.otherBusinessName ?? '',
                    chatColor: _chatColor,
                    onRemove: _clearReply,
                  ),
                if (_productReference != null)
                  _ProductReferenceCard(
                    reference: _productReference!,
                    chatColor: _chatColor,
                    onRemove: _removeReference,
                  ),
                // Media preview
                if (_isProcessingCapture)
                  Container(
                    height: 40,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.pureSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.whisperBorder),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Processing recorded video…',
                          style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                        ),
                      ],
                    ),
                  ),
                if (_pendingMediaList.isNotEmpty)
                  Container(
                    height: 86,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.pureSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.whisperBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _pendingMediaList.length,
                            itemExtent: 78,
                            itemBuilder: (context, idx) {
                              final file = _pendingMediaList[idx];
                              final isVideo = _pendingIsVideoList[idx];
                              final isCamera = idx < _pendingMediaSourceList.length &&
                                  _pendingMediaSourceList[idx] == 'camera';
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 70,
                                height: 70,
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _buildPendingMediaThumbnail(
                                        file,
                                        isVideo,
                                        idx < _pendingVideoThumbList.length ? _pendingVideoThumbList[idx] : null,
                                      ),
                                    ),
                                    if (isCamera)
                                      Positioned(
                                        left: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.65),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _RecordingDot(size: 6),
                                              SizedBox(width: 3),
                                              Text(
                                                'REC',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _pendingMediaList.removeAt(idx);
                                            _pendingIsVideoList.removeAt(idx);
                                            _pendingVideoThumbList.removeAt(idx);
                                            if (idx < _pendingMediaSourceList.length) {
                                              _pendingMediaSourceList.removeAt(idx);
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.plus, size: 20),
                          foregroundColor: _chatColor,
                          onPressed: _pickMedia,
                        ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: _isRecording
                        ? Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.pureSurface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppTheme.whisperBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(LucideIcons.trash2, color: AppTheme.destructive, size: 20),
                                  onPressed: _cancelRecording,
                                ),
                                // Pause / resume — pauses the mic session in
                                // place; resuming continues the same take.
                                IconButton(
                                  icon: Icon(
                                    _isRecordingPaused ? LucideIcons.play : LucideIcons.pause,
                                    color: AppTheme.charcoalInk,
                                    size: 20,
                                  ),
                                  tooltip: _isRecordingPaused ? 'Resume' : 'Pause',
                                  onPressed: _isRecordingPaused ? _resumeRecording : _pauseRecording,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Container(
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: _isRecordingPaused
                                          ? AppTheme.mutedSteel.withValues(alpha: 0.12)
                                          : AppTheme.destructive.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Row(
                                      children: [
                                        _BlinkingRedDot(paused: _isRecordingPaused),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDuration(_recordDurationSeconds),
                                          style: TextStyle(
                                            color: _isRecordingPaused ? AppTheme.mutedSteel : AppTheme.destructive,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (_isRecordingPaused) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Paused',
                                            style: TextStyle(
                                              color: AppTheme.mutedSteel,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Center(
                                            child: _VoiceRecordingWave(paused: _isRecordingPaused),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _chatColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
                                    onPressed: _stopAndSendRecording,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.pureSurface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.whisperBorder),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(LucideIcons.paperclip, size: 20),
                                  color: AppTheme.mutedSteel,
                                  onPressed: (_isSendingMedia || _isProcessingCapture) ? null : _pickMedia,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.pureSurface,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: AppTheme.whisperBorder),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.only(left: 14, right: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _messageCtrl,
                                          focusNode: _messageFocusNode,
                                          decoration: InputDecoration(
                                            hintText: _pendingMediaList.isNotEmpty ? 'Add a caption...' : 'Type a message...',
                                            hintStyle: const TextStyle(
                                              color: AppTheme.mutedSteel,
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          style: TextStyle(fontSize: context.rsp(14), color: AppTheme.charcoalInk),
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => _sendMessage(),
                                          minLines: 1,
                                          maxLines: 5,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(LucideIcons.smile, size: 20, color: AppTheme.mutedSteel),
                                        onPressed: _openGifPicker,
                                        splashRadius: 18,
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Builder(
                                builder: (context) {
                                  final hasInput = _messageCtrl.text.trim().isNotEmpty ||
                                      _pendingMediaList.isNotEmpty ||
                                      _productReference != null;

                                  if (_isSendingMedia) {
                                    return Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.pureSurface,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppTheme.whisperBorder),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    );
                                  }

                                  return Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: hasInput ? _chatColor : AppTheme.pureSurface,
                                      shape: BoxShape.circle,
                                      border: hasInput ? null : Border.all(color: AppTheme.whisperBorder),
                                      boxShadow: [
                                        BoxShadow(
                                          color: hasInput
                                              ? _chatColor.withValues(alpha: 0.35)
                                              : Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        hasInput ? LucideIcons.send : LucideIcons.mic,
                                        size: 20,
                                        color: hasInput ? Colors.white : AppTheme.mutedSteel,
                                      ),
                                      onPressed: hasInput ? _sendMessage : _startRecording,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyPreviewCard extends StatelessWidget {
  final Message message;
  final String currentUserId;
  final String otherUserName;
  final bool otherUserVerified;
  final String otherBusinessName;
  final Color chatColor;
  final VoidCallback onRemove;

  const _ReplyPreviewCard({
    required this.message,
    required this.currentUserId,
    required this.otherUserName,
    this.otherUserVerified = false,
    this.otherBusinessName = '',
    required this.chatColor,
    required this.onRemove,
  });

  String _truncateName(String name) {
    if (name.length > 20) {
      return '${name.substring(0, 17)}...';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final isMe = message.senderId == currentUserId;
    final displayName = isMe
        ? 'You'
        : _truncateName(otherBusinessName.isNotEmpty
            ? otherBusinessName
            : (otherUserName.isNotEmpty ? otherUserName : (message.replyToSenderName ?? 'User')));
    final hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
    final isVideo = message.mediaType == 'video';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: chatColor, width: 3.5),
          top: const BorderSide(color: AppTheme.whisperBorder),
          right: const BorderSide(color: AppTheme.whisperBorder),
          bottom: const BorderSide(color: AppTheme.whisperBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: chatColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isMe && otherUserVerified) ...[
                      const SizedBox(width: 3),
                      VerificationBadge(size: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasMedia
                      ? (isVideo ? '\u{1F4F9} Video' : '\u{1F4F7} Photo')
                      : message.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
          if (hasMedia && message.mediaUrl != null) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: isVideo
                  ? Container(
                      width: 40,
                      height: 40,
                      color: AppTheme.charcoalInk,
                      child: const Center(child: Icon(LucideIcons.play, size: 16, color: Colors.white)),
                    )
                  : CachedNetworkImage(
                      imageUrl: message.mediaUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      memCacheWidth: 40,
                    ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(LucideIcons.x, size: 18, color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }
}

class _ProductReferenceCard extends StatelessWidget {
  final Map<String, dynamic> reference;
  final Color chatColor;
  final VoidCallback onRemove;

  const _ProductReferenceCard({
    required this.reference,
    required this.chatColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = reference['image_url'] as String?;
    final title = reference['title'] as String? ?? '';
    final price = (reference['price'] as num?)?.toDouble() ?? 0;
    final isService = (reference['type'] as String?) == 'service';
    final packageName = reference['package_name'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.whisperBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: chatColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 48,
                height: 48,
                memCacheWidth: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: AppTheme.warmMist,
                  child: const Icon(LucideIcons.image, size: 24, color: AppTheme.mutedSteel),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AppTheme.warmMist,
                  child: const Icon(LucideIcons.image, size: 24, color: AppTheme.mutedSteel),
                ),
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isService ? LucideIcons.briefcaseBusiness : LucideIcons.package,
                color: AppTheme.mutedSteel,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (packageName != null && packageName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Package: $packageName',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.mutedSteel,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        formatGhs(price),
                        style: TextStyle(
                          fontSize: 12,
                          color: chatColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isService) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: chatColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Service',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: chatColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 18),
            foregroundColor: AppTheme.mutedSteel,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isHighlighted;
  final Color chatColor;
  // Conversation-wide media gallery (oldest → newest) so the viewer can
  // swipe between every image/video in this chat, WhatsApp-style.
  final List<String>? conversationMediaUrls;
  final List<String?>? conversationMediaThumbnails;
  final int conversationMediaIndex;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onReplyTap;
  final void Function(bool isVideo)? onCallback;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHighlighted = false,
    required this.chatColor,
    this.conversationMediaUrls,
    this.conversationMediaThumbnails,
    this.conversationMediaIndex = 0,
    this.onLongPress,
    this.onTap,
    this.onSwipeReply,
    this.onReplyTap,
    this.onCallback,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _highlightAnimCtrl;
  late Animation<double> _highlightAnim;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _highlightAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _highlightAnim = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _highlightAnimCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _highlightAnimCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _highlightAnimCtrl.dispose();
    super.dispose();
  }

  Widget _buildStatusIndicator(Message msg) {
    final status = msg.status;
    switch (status) {
      case 'sent':
        return Icon(LucideIcons.check, size: 12, color: Colors.white.withValues(alpha: 0.6));
      case 'delivered':
        return Icon(LucideIcons.checkCheck, size: 12, color: Colors.white.withValues(alpha: 0.6));
      case 'seen':
        return Icon(LucideIcons.checkCheck, size: 12, color: Colors.white);
      default:
        return Icon(LucideIcons.check, size: 12, color: Colors.white.withValues(alpha: 0.6));
    }
  }

  Widget _buildReplyQuote() {
    final msg = widget.message;
    if (!msg.isReply) return const SizedBox.shrink();

    final replyContent = msg.replyToContent ?? '';
    final replySender = msg.replyToSenderName ?? '';
    final hasReplyMedia = msg.replyToMediaUrl != null && msg.replyToMediaUrl!.isNotEmpty;
    final isReplyMediaVideo = msg.replyToMediaType == 'video';

    return GestureDetector(
      onTap: widget.onReplyTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.15)
              : AppTheme.warmMist,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: widget.isMe ? Colors.white.withValues(alpha: 0.5) : widget.chatColor,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    replySender,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.isMe ? Colors.white.withValues(alpha: 0.9) : widget.chatColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasReplyMedia
                        ? (isReplyMediaVideo ? '\u{1F4F9} Video' : '\u{1F4F7} Photo')
                        : replyContent,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isMe ? Colors.white.withValues(alpha: 0.7) : AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            if (hasReplyMedia && msg.replyToMediaUrl != null) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: isReplyMediaVideo
                    ? Container(
                        width: 36,
                        height: 36,
                        color: AppTheme.charcoalInk,
                        child: const Center(child: Icon(LucideIcons.play, size: 14, color: Colors.white)),
                      )
                    : CachedNetworkImage(
                        imageUrl: msg.replyToMediaUrl!,
                        cacheManager: ChatMediaCacheManager(),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        memCacheWidth: 36,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isCall = msg.isCall;
    final hasMedia = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty && !isCall;
    final hasProduct = msg.productReference != null && !isCall;
    final hasContent = msg.content.isNotEmpty && !isCall;
    final isVoice = msg.mediaType == 'voice' && !isCall;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: widget.onTap,
      onHorizontalDragStart: (_) => _dragOffset = 0,
      onHorizontalDragUpdate: (details) {
        if (!widget.isMe) {
          // Left-to-right swipe for received messages
          _dragOffset = (_dragOffset + details.delta.dx).clamp(0, 120);
        } else {
          // Right-to-left swipe for sent messages
          _dragOffset = (_dragOffset + details.delta.dx).clamp(-120, 0);
        }
      },
      onHorizontalDragEnd: (details) {
        final threshold = 80.0;
        if ((!widget.isMe && _dragOffset > threshold) ||
            (widget.isMe && _dragOffset < -threshold)) {
          widget.onSwipeReply?.call();
        }
        _dragOffset = 0;
      },
      child: AnimatedBuilder(
        animation: _highlightAnim,
        builder: (context, child) {
          return Container(
            color: widget.isHighlighted
                ? widget.chatColor.withValues(alpha: _highlightAnim.value)
                : Colors.transparent,
            child: child,
          );
        },
        child: Stack(
          children: [
            // Reply indicator icon during drag
            if (_dragOffset.abs() > 20)
              Positioned(
                left: widget.isMe ? null : 0,
                right: widget.isMe ? 0 : null,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: (_dragOffset.abs() / 80).clamp(0, 1),
                    child: Icon(
                      LucideIcons.reply,
                      size: 20,
                      color: widget.chatColor,
                    ),
                  ),
                ),
              ),
            // Selection checkmark — sits inside the 28px margin the bubble
            // reserves on its outer edge. (A negative offset here would render
            // outside the Stack, which clips it via Clip.hardEdge.)
            if (widget.isSelectionMode && widget.isMe)
              Positioned(
                right: 3,
                top: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? widget.chatColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected ? widget.chatColor : AppTheme.whisperBorder,
                      width: 1.5,
                    ),
                  ),
                  child: widget.isSelected
                      ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            // Main bubble
            Align(
              alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(
                  bottom: 8,
                  left: widget.isMe ? 0 : (widget.isSelectionMode ? 28 : 0),
                  right: widget.isMe ? (widget.isSelectionMode ? 28 : 0) : 0,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: hasMedia && !isVoice && !hasContent && !hasProduct ? 4 : 14,
                  vertical: hasMedia && !isVoice && !hasContent && !hasProduct ? 4 : 10,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? (widget.isMe ? widget.chatColor.withValues(alpha: 0.8) : AppTheme.pureSurface.withValues(alpha: 0.8))
                      : (widget.isMe ? widget.chatColor : AppTheme.pureSurface),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
                    bottomRight: Radius.circular(widget.isMe ? 4 : 16),
                  ),
                  border: widget.isMe ? null : Border.all(color: AppTheme.whisperBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCall)
                      _CallBubbleContent(
                        message: msg,
                        isMe: widget.isMe,
                        chatColor: widget.chatColor,
                        onCallback: widget.onCallback,
                      )
                    else ...[
                      if (msg.isReply) _buildReplyQuote(),
                      if (hasMedia)
                        if (isVoice)
                          _VoiceBubbleContent(message: msg, isMe: widget.isMe, chatColor: widget.chatColor)
                        else
                          _MediaBubbleContent(
                            message: msg,
                            isMe: widget.isMe,
                            mediaUrls: widget.conversationMediaUrls,
                            thumbnails: widget.conversationMediaThumbnails,
                            initialIndex: widget.conversationMediaIndex,
                          ),
                      if (hasProduct)
                        _InlineProductCard(
                          reference: msg.productReference,
                          isMe: widget.isMe,
                          chatColor: widget.chatColor,
                        ),
                      if (hasContent)
                        Padding(
                          padding: EdgeInsets.only(
                            top: (hasProduct || (hasMedia && !isVoice) || msg.isReply) ? 8 : 0,
                            left: hasMedia && !isVoice ? 10 : 0,
                            right: hasMedia && !isVoice ? 10 : 0,
                          ),
                          child: Linkify(
                            onOpen: (link) async {
                              final uri = Uri.parse(link.url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            text: msg.content,
                            style: TextStyle(
                              color: widget.isMe ? Colors.white : AppTheme.charcoalInk,
                            ),
                            linkStyle: TextStyle(
                              color: widget.isMe ? Colors.yellow : widget.chatColor,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                    ],
                    Padding(
                      padding: EdgeInsets.only(
                        left: (hasMedia || isCall) ? 8 : 0,
                        right: (hasMedia || isCall) ? 8 : 0,
                        top: isCall ? 2 : 4,
                        bottom: hasMedia ? 6 : 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(msg.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : AppTheme.mutedSteel,
                            ),
                          ),
                          if (widget.isMe) ...[
                            const SizedBox(width: 4),
                            _buildStatusIndicator(msg),
                          ],
                          if (widget.isMe && msg.status == 'seen' && msg.seenAt != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              'Seen ${DateFormat('HH:mm').format(msg.seenAt!)}',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.6),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Solid red dot used to mark in-app camera recordings (REC chip, bubble
/// badge). Drawn as a plain circle so it doesn't depend on icon-font fill.
class _RecordingDot extends StatelessWidget {
  final double size;
  const _RecordingDot({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    );
  }
}

class _MediaBubbleContent extends StatelessWidget {
  final dynamic message;
  final bool isMe;
  // Full conversation media (oldest → newest) + this bubble's position in
  // it; null when the caller didn't provide a gallery (fallback: single).
  final List<String>? mediaUrls;
  final List<String?>? thumbnails;
  final int initialIndex;

  const _MediaBubbleContent({
    required this.message,
    required this.isMe,
    this.mediaUrls,
    this.thumbnails,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl as String;
    final isVideo = message.mediaType == 'video';
    final thumbnail = message.thumbnailUrl;

    return GestureDetector(
      onTap: () {
        final gallery = (mediaUrls != null && mediaUrls!.isNotEmpty)
            ? mediaUrls!
            : [url];
        final index = gallery.length == 1 ? 0 : initialIndex.clamp(0, gallery.length - 1);
        MediaViewer.open(
          context,
          gallery,
          cacheManager: ChatMediaCacheManager(),
          initialIndex: index,
          thumbnailUrls: thumbnails,
        );
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isVideo)
              // Preview frame extracted at send time; fall back to an icon
              // for videos without one (e.g. sent from web).
              if (thumbnail != null)
                CachedNetworkImage(
                  imageUrl: thumbnail,
                  cacheManager: ChatMediaCacheManager(),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  placeholder: (_, _) => Container(
                    height: 200,
                    color: AppTheme.charcoalInk,
                    child: const Center(
                      child: Icon(LucideIcons.film, size: 48, color: Colors.white54),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 200,
                    color: AppTheme.charcoalInk,
                    child: const Center(
                      child: Icon(LucideIcons.film, size: 48, color: Colors.white54),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  height: 200,
                  color: AppTheme.charcoalInk,
                  child: const Center(
                    child: Icon(LucideIcons.film, size: 48, color: Colors.white54),
                  ),
                )
            else
              CachedNetworkImage(
                imageUrl: url,
                cacheManager: ChatMediaCacheManager(),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (_, _) => Container(
                  height: 200,
                  color: AppTheme.warmMist,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => Container(
                  height: 200,
                  color: AppTheme.warmMist,
                  child: const Center(
                    child: Icon(LucideIcons.imageOff, size: 32, color: AppTheme.mutedSteel),
                  ),
                ),
              ),
            if (isVideo)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.play, color: Colors.white, size: 28),
              ),
            // Provenance badge — recordings made in-app are marked with a
            // red dot; gallery picks (and legacy videos, which could only
            // come from the gallery) show a gallery label.
            if (isVideo)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: message.isCameraVideo
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RecordingDot(size: 7),
                            SizedBox(width: 4),
                            Text(
                              'Recorded',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.image, size: 11, color: Colors.white70),
                            SizedBox(width: 4),
                            Text(
                              'Gallery',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InlineProductCard extends StatelessWidget {
  final dynamic reference;
  final bool isMe;
  final Color chatColor;

  const _InlineProductCard({required this.reference, required this.isMe, required this.chatColor});

  @override
  Widget build(BuildContext context) {
    final imageUrl = reference.imageUrl as String?;
    final title = reference.title as String? ?? '';
    final price = (reference.price as num?)?.toDouble() ?? 0;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final productId = reference.productId as String?;
    final isService = reference.isService == true;
    final packageName = reference.packageName as String?;

    return GestureDetector(
      onTap: productId != null
          ? () => Navigator.of(context).pushNamed(
              isService ? '/service-detail' : '/product',
              arguments: productId,
            )
          : null,
      child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : AppTheme.warmMist,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                memCacheWidth: 360,
                placeholder: (_, _) => Container(
                  height: 120,
                  color: AppTheme.mutedSteel.withValues(alpha: 0.2),
                  child: const Center(
                    child: Icon(LucideIcons.image, size: 32, color: AppTheme.mutedSteel),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  height: 120,
                  color: AppTheme.mutedSteel.withValues(alpha: 0.2),
                  child: const Center(
                    child: Icon(LucideIcons.imageOff, size: 32, color: AppTheme.mutedSteel),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (!hasImage)
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.mutedSteel.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isService ? LucideIcons.briefcaseBusiness : LucideIcons.package,
                          size: 20,
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isMe ? Colors.white : AppTheme.charcoalInk,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (packageName != null && packageName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Package: $packageName',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : AppTheme.mutedSteel,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  formatGhs(price),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isMe ? Colors.white.withValues(alpha: 0.9) : chatColor,
                                  ),
                                ),
                              ),
                              if (isService) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : chatColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Service',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isMe
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : chatColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (productId != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        isService ? LucideIcons.briefcaseBusiness : LucideIcons.externalLink,
                        size: 11,
                        color: isMe ? Colors.white.withValues(alpha: 0.7) : chatColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isService ? 'View Service' : 'View Product',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white.withValues(alpha: 0.7) : chatColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _MediaOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MediaOption({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlinkingRedDot extends StatefulWidget {
  final bool paused;

  const _BlinkingRedDot({this.paused = false});

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: widget.paused ? 1.0 : 0.0,
    );
    if (!widget.paused) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_BlinkingRedDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        // Solid dot while paused instead of freezing mid-fade.
        _controller.stop();
        _controller.value = 1.0;
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CallBubbleContent extends StatelessWidget {
  final Message message;
  final bool isMe;
  final Color chatColor;
  final void Function(bool isVideo)? onCallback;

  const _CallBubbleContent({
    required this.message,
    required this.isMe,
    required this.chatColor,
    this.onCallback,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = message.callType == 'video';
    final status = message.callStatus;
    final duration = message.callDuration;

    final isMissed = status == 'missed' || status == 'no_answer';
    final isDeclined = status == 'declined';
    final isCancelled = status == 'cancelled';
    final isBusy = status == 'busy';
    final isFailed = isMissed || isDeclined || isCancelled || isBusy;

    // WhatsApp-style Title
    final String title;
    if (!isMe && isMissed) {
      title = isVideo ? 'Missed video call' : 'Missed voice call';
    } else if (!isMe && isDeclined) {
      title = isVideo ? 'Declined video call' : 'Declined voice call';
    } else if (isMe && isMissed) {
      title = isVideo ? 'Unanswered video call' : 'Unanswered voice call';
    } else if (isMe && isDeclined) {
      title = isVideo ? 'Declined video call' : 'Declined voice call';
    } else if (isCancelled) {
      title = isVideo ? 'Cancelled video call' : 'Cancelled voice call';
    } else if (isBusy) {
      title = isVideo ? 'Busy video call' : 'Busy voice call';
    } else {
      title = isVideo ? 'Video call' : 'Voice call';
    }

    // WhatsApp-style Subtitle (Duration if > 0, formatted with hours if > 60m)
    final String subtitle;
    if (duration > 0) {
      subtitle = formatCallDuration(duration);
    } else if (isMissed) {
      subtitle = isMe ? 'No answer' : 'Missed';
    } else if (isDeclined) {
      subtitle = 'Declined';
    } else if (isCancelled) {
      subtitle = 'Cancelled';
    } else if (isBusy) {
      subtitle = 'Busy';
    } else {
      subtitle = 'Ended';
    }

    // Call icon & tinting
    final IconData iconData;
    final Color iconColor;
    if (isVideo) {
      if (isFailed && !isMe) {
        iconData = LucideIcons.videoOff;
        iconColor = Colors.redAccent;
      } else {
        iconData = LucideIcons.video;
        iconColor = isMe
            ? Colors.white
            : (isFailed ? Colors.redAccent : chatColor);
      }
    } else {
      if (!isMe && isMissed) {
        iconData = LucideIcons.phoneMissed;
        iconColor = Colors.redAccent;
      } else if (!isMe && isDeclined) {
        iconData = LucideIcons.phoneOff;
        iconColor = Colors.redAccent;
      } else if (!isMe && !isFailed) {
        iconData = LucideIcons.phoneIncoming;
        iconColor = isMe ? Colors.white : AppTheme.successMoss;
      } else if (isMe && isFailed) {
        iconData = LucideIcons.phoneOff;
        iconColor = isMe ? Colors.white.withValues(alpha: 0.85) : Colors.redAccent;
      } else {
        iconData = LucideIcons.phoneOutgoing;
        iconColor = isMe ? Colors.white : chatColor;
      }
    }

    final badgeBg = isMe
        ? Colors.white.withValues(alpha: 0.18)
        : (isFailed && !isMe
            ? Colors.red.withValues(alpha: 0.1)
            : chatColor.withValues(alpha: 0.1));

    return InkWell(
      onTap: onCallback != null ? () => onCallback!(isVideo) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                size: 19,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isMe
                          ? Colors.white
                          : (isFailed && !isMe ? Colors.redAccent : AppTheme.charcoalInk),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.22)
                    : chatColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  isVideo ? LucideIcons.video : LucideIcons.phone,
                  size: 16,
                  color: isMe ? Colors.white : chatColor,
                ),
                onPressed: onCallback != null ? () => onCallback!(isVideo) : null,
                tooltip: isVideo ? 'Video call back' : 'Call back',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceBubbleContent extends StatefulWidget {
  final Message message;
  final bool isMe;
  final Color chatColor;

  const _VoiceBubbleContent({required this.message, required this.isMe, required this.chatColor});

  @override
  State<_VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends State<_VoiceBubbleContent> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  Future<void>? _downloadFuture;
  AudioPlayer? _player;
  Source? _audioSource;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    _checkIfDownloaded().then((_) {
      // Voice notes live on device storage: fetch any note that isn't
      // local yet as soon as it appears (silent — play still falls back
      // to streaming if the download can't complete right now).
      if (!mounted || kIsWeb || _isDownloaded) return;
      _downloadFuture = _downloadVoiceNote(automatic: true);
    });
  }

  Future<void> _checkIfDownloaded() async {
    try {
      if (kIsWeb) {
        // On web, voice notes are always streamed from network.
        if (mounted) setState(() { _isDownloaded = false; });
        return;
      }
      final path = await _getLocalFilePath();
      final exists = await RecordingHelper.fileExists(path);
      if (mounted) {
        setState(() {
          _isDownloaded = exists;
        });
      }
    } catch (_) {}
  }

  Future<String> _getLocalFilePath() async {
    final uri = Uri.parse(widget.message.mediaUrl!);
    final filename = uri.pathSegments.last;
    final docsDir = await RecordingHelper.getDocsDir();
    final voiceNotesDir = '$docsDir/voice_notes';
    return '$voiceNotesDir/$filename';
  }

  Future<void> _downloadVoiceNote({bool automatic = false}) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });

    try {
      final response = await http.get(Uri.parse(widget.message.mediaUrl!));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (!kIsWeb) {
          // On mobile, save to local file for offline playback.
          final path = await _getLocalFilePath();
          final file = File(path);
          await file.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes);
        }
        if (mounted) {
          setState(() {
            _isDownloaded = true;
            _isDownloading = false;
          });
        }

        // Delete from R2 storage only after successful save
        try {
          await StorageService.deleteImage(widget.message.mediaUrl!);
        } catch (e) {
          debugPrint('Error deleting voice note from R2: $e');
        }
      } else {
        throw Exception('Download failed with status: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        // Background fetches fail silently (offline, or another device
        // already pulled the note off R2); only user-triggered downloads
        // surface a toast.
        if (!automatic) {
          ShadToaster.of(context).show(
            ShadToast(title: Text('Failed to download voice note: $e')),
          );
        }
      }
    }
  }

  Future<void> _initPlayer() async {
    if (_player != null) return;
    final player = AudioPlayer();
    
    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _posSub = player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _durSub = player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });

    try {
      if (!kIsWeb) {
        final filePath = await _getLocalFilePath();
        final file = File(filePath);
        if (await file.exists() && await file.length() > 0) {
          _audioSource = DeviceFileSource(filePath);
        } else {
          _audioSource = UrlSource(widget.message.mediaUrl!);
        }
      } else {
        _audioSource = UrlSource(widget.message.mediaUrl!);
      }
    } catch (e) {
      debugPrint('Error setting audio source: $e');
      _audioSource = UrlSource(widget.message.mediaUrl!);
    }
    await player.setSource(_audioSource!);
    
    _player = player;
  }

  Future<void> _togglePlay() async {
    try {
      if (!_isDownloaded) {
        // If the automatic background download is already running, wait
        // for it instead of racing a second one.
        await (_downloadFuture ??= _downloadVoiceNote());
        if (_isDownloaded) {
          await _initPlayer();
          if (_player != null && _audioSource != null) {
            await _player!.play(_audioSource!);
          }
        }
        return;
      }

      await _initPlayer();

      if (_isPlaying) {
        await _player?.pause();
      } else {
        // If duration is 0, player may have failed to load - reset and retry
        if (_duration == Duration.zero && _player != null) {
          await _player!.dispose();
          _player = null;
          _audioSource = null;
          await _stateSub?.cancel();
          await _posSub?.cancel();
          await _durSub?.cancel();
          await _initPlayer();
        }
        if (_audioSource != null) {
          await _player?.play(_audioSource!);
        }
      }
    } catch (e) {
      debugPrint('Error toggling playback: $e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isMe ? Colors.white : widget.chatColor;
    final textColor = widget.isMe ? Colors.white70 : AppTheme.mutedSteel;

    return SizedBox(
      width: 230,
      child: Row(
        children: [
          // Play/Pause/Download button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white24 : AppTheme.warmMist,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _isDownloading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      )
                    : !_isDownloaded
                        ? Icon(
                            LucideIcons.download,
                            size: 18,
                            color: accentColor,
                          )
                        : Icon(
                            _isPlaying ? LucideIcons.pause : LucideIcons.play,
                            size: 18,
                            color: accentColor,
                          ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform/Slider and Duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isDownloaded)
                  Text(
                    'Tap to download',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.isMe ? Colors.white : AppTheme.charcoalInk,
                    ),
                  )
                else
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                      activeTrackColor: widget.isMe ? Colors.white : widget.chatColor,
                      inactiveTrackColor: widget.isMe ? Colors.white38 : AppTheme.whisperBorder,
                      thumbColor: widget.isMe ? Colors.white : widget.chatColor,
                      overlayColor: widget.isMe ? Colors.white12 : widget.chatColor.withValues(alpha: 0.1),
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: _duration.inMilliseconds.toDouble() > 0
                          ? _duration.inMilliseconds.toDouble()
                          : 100.0,
                      onChanged: (value) async {
                        if (_player != null) {
                          await _player!.seek(Duration(milliseconds: value.toInt()));
                        }
                      },
                    ),
                  ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.mic,
                          size: 12,
                          color: textColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Voice Note',
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    if (_isDownloaded)
                      Text(
                        '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: textColor,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRecordingWave extends StatefulWidget {
  final bool paused;

  const _VoiceRecordingWave({this.paused = false});

  @override
  State<_VoiceRecordingWave> createState() => _VoiceRecordingWaveState();
}

class _VoiceRecordingWaveState extends State<_VoiceRecordingWave> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = [
    8, 14, 10, 18, 22, 12, 16, 10, 20, 24,
    20, 14, 16, 10, 20, 26, 14, 16, 10, 15,
    10, 16, 22, 12, 18, 14, 8, 12, 10, 6
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (!widget.paused) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_VoiceRecordingWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused != oldWidget.paused) {
      // Freezing mid-cycle keeps the bars at their current shape while
      // paused — reads as "frozen", then springs back to life on resume.
      if (widget.paused) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_barHeights.length, (index) {
            final phase = (index / _barHeights.length) * 2 * math.pi;
            final scale = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi - phase));
            final height = _barHeights[index] * scale;

            return Container(
              width: 2.5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: BoxDecoration(
                color: widget.paused
                    ? AppTheme.mutedSteel.withValues(alpha: 0.5)
                    : AppTheme.destructive.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(1.25),
              ),
            );
          }),
        );
      },
    );
  }
}


class _VideoTrimDialog extends StatefulWidget {
  final dynamic file;
  final int maxSeconds;

  const _VideoTrimDialog({required this.file, required this.maxSeconds});

  @override
  State<_VideoTrimDialog> createState() => _VideoTrimDialogState();
}

class _VideoTrimDialogState extends State<_VideoTrimDialog> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  double _startSecond = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // On web, this dialog is never shown (kIsWeb guard in _handleVideoPicked).
    // On mobile, widget.file is a dart:io File.
    _controller = VideoPlayerController.networkUrl(Uri.parse('about:blank'))
      ..initialize().then((_) {
        if (mounted) setState(() { _initialized = true; });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(double seconds) {
    final mins = seconds.toInt() ~/ 60;
    final secs = seconds.toInt() % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Dialog(
        backgroundColor: AppTheme.pureSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading video info...', style: TextStyle(color: AppTheme.mutedSteel)),
            ],
          ),
        ),
      );
    }

    final totalSecs = _controller.value.duration.inSeconds;
    final maxSliderVal = (totalSecs - widget.maxSeconds).toDouble().clamp(0.0, totalSecs.toDouble());

    return Dialog(
      backgroundColor: AppTheme.pureSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              color: AppTheme.accent.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(LucideIcons.scissors, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Trim Video (Max 15s)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.charcoalInk),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ${_formatDuration(totalSecs.toDouble())}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.black,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                          _isPlaying = false;
                        } else {
                          _controller.play();
                          _isPlaying = true;
                        }
                      });
                    },
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.black45,
                      child: Icon(
                        _isPlaying ? LucideIcons.pause : LucideIcons.play,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Start: ${_formatDuration(_startSecond)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('End: ${_formatDuration(_startSecond + widget.maxSeconds)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent)),
                    ],
                  ),
                  Slider(
                    activeColor: AppTheme.accent,
                    inactiveColor: AppTheme.whisperBorder,
                    min: 0,
                    max: maxSliderVal == 0 ? 0.1 : maxSliderVal,
                    value: _startSecond.clamp(0.0, maxSliderVal == 0 ? 0.1 : maxSliderVal),
                    onChanged: maxSliderVal == 0 ? null : (val) {
                      setState(() {
                        _startSecond = val;
                      });
                      _controller.seekTo(Duration(seconds: _startSecond.toInt()));
                    },
                  ),
                  const Text(
                    'Drag slider to select the 15-second window to send.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.ghost(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.of(context).pop(_startSecond.toInt()),
                    child: const Text('Trim & Send'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
