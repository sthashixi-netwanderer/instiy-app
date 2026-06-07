import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:giphy_get/giphy_get.dart';
import '../../config/app_theme.dart';
import '../../services/secrets_service.dart';
import '../../utils/responsive.dart';
import '../../models/message_model.dart';
import '../../providers/providers.dart';
import '../../widgets/verification_badge.dart';
import '../../providers/message_provider.dart';


import '../../services/storage_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/skeleton.dart';
import 'report_screen.dart';
import 'archived_chats_screen.dart';
import 'blocked_chats_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messageProvider).loadConversations();
      ref.read(blockProvider).ensureInitialized();
    });
  }

  @override
  Widget build(BuildContext context) {
    final msgProv = ref.watch(messageProvider);
    final authProv = ref.watch(authProvider);
    final blockProv = ref.watch(blockProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Messages'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(child: Text('Sign in to view your messages')),
      );
    }

    // Filter out conversations with blocked users
    final conversations = msgProv.conversations
        .where((c) => !blockProv.isUserBlocked(c.otherUserId))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBody: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Messages'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
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
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
      body: RefreshIndicator(
        onRefresh: () => msgProv.loadConversations(),
        child: msgProv.isLoading && conversations.isEmpty
            ? const ListSkeleton(count: 8)
            : conversations.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
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
    }
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
  List<File> _pendingMediaList = [];
  List<bool> _pendingIsVideoList = [];
  String? _firstUnreadMessageId;
  bool _hasSetInitialScroll = false;
  bool _showScrollDownButton = false;
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
  String? _recordPath;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  final _audioRecorder = AudioRecorder();

  final FocusNode _messageFocusNode = FocusNode();

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
  }

  void _scrollListener() {
    if (!_scrollCtrl.hasClients) return;
    final show = _scrollCtrl.offset < _scrollCtrl.position.maxScrollExtent - 300;
    if (show != _showScrollDownButton) {
      setState(() {
        _showScrollDownButton = show;
      });
    }

    // Load older messages when scrolled near the top
    if (_scrollCtrl.offset < 200) {
      final msgProv = ref.read(messageProvider);
      if (!msgProv.isLoadingMoreMessages && msgProv.hasMoreMessages) {
        msgProv.loadMoreMessages(widget.conversation.id);
      }
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _captionCtrl.dispose();
    _scrollCtrl.dispose();
    _messageFocusNode.dispose();
    _messageProvider.disposeConversation();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _removeReference() {
    setState(() {
      _productReference = null;
    });
  }

  void _handleMenuAction(String action, String otherUserId, bool isBlocked) {
    switch (action) {
      case 'block':
        _showBlockConfirmation(otherUserId);
        break;
      case 'unblock':
        _unblockUser(otherUserId);
        break;
      case 'report':
        _openReportScreen(otherUserId);
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

  void _scrollToMessage(String messageId) {
    final messages = _messageProvider.messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    // Using Future.delayed to ensure the ScrollController has registered clients and correct scroll extent
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final targetOffset = (index * 75.0).clamp(
        0.0,
        _scrollCtrl.position.maxScrollExtent,
      );

      _scrollCtrl.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

    // Highlight the message
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
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
        );
      }
      _messageCtrl.clear();
      setState(() {
        _pendingMediaList = [];
        _pendingIsVideoList = [];
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

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickMedia() async {
    final source = await _showMediaSourceSheet();
    if (source == null) return;

    if (source == 'gif') {
      _openGifPicker();
      return;
    }

    final picker = ImagePicker();
    final isVideo = source == 'video';

    if (isVideo) {
      final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
      if (picked == null) return;
      await _handleVideoPicked(File(picked.path));
    } else {
      final pickedList = await picker.pickMultiImage(maxWidth: 1080, maxHeight: 1080, imageQuality: 60);
      if (pickedList.isEmpty) return;
      for (final picked in pickedList) {
        await _handleImagePicked(File(picked.path));
      }
    }
  }

  Future<void> _handleImagePicked(File file) async {
    setState(() {
      _pendingMediaList.add(file);
      _pendingIsVideoList.add(false);
    });
  }

  Future<void> _handleVideoPicked(File file) async {
    // Check duration and trim if > 15s
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    final duration = controller.value.duration;
    await controller.dispose();

    File fileToSend = file;
    if (duration.inSeconds > 15) {
      if (!mounted) return;
      final startSecond = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _VideoTrimDialog(file: file, maxSeconds: 15),
      );

      if (startSecond == null) {
        // User cancelled trimming, skip sending
        return;
      }

      final trimmed = await _trimVideo(file, maxSeconds: 15, startSecond: startSecond);
      if (trimmed != null) {
        fileToSend = trimmed;
      }
    }

    // Compress video to reduce file size
    final compressed = await _compressVideo(fileToSend);
    if (compressed != null) {
      fileToSend = compressed;
    }

    setState(() {
      _pendingMediaList.add(fileToSend);
      _pendingIsVideoList.add(true);
    });
  }

  void clearPendingMedia() {
    setState(() {
      _pendingMediaList.clear();
      _pendingIsVideoList.clear();
    });
  }

  Future<void> _openGifPicker() async {
    // Dismiss system keyboard
    FocusScope.of(context).unfocus();
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

  Future<File?> _trimVideo(File file, {required int maxSeconds, int startSecond = 0}) async {
    // Offloaded to backend for low-end device optimization
    return file;
  }

  Future<File?> _compressVideo(File file) async {
    // Offloaded to backend for low-end device optimization
    return file;
  }

  void _sendMediaFireAndForget({
    required File file,
    required String mediaType,
    required String caption,
    String? replyToMessageId,
  }) {
    setState(() => _isSendingMedia = true);

    // Clear input immediately so user can type next message
    _messageCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    () async {
      try {
        final folder = 'chat-media/${mediaType == 'video' ? 'videos' : 'images'}';
        final url = mediaType == 'video'
            ? await StorageService.uploadFile(file: file, folder: folder, contentType: 'video/mp4', extension: 'mp4')
            : await StorageService.uploadImage(file: file, folder: folder);

        if (mounted) {
          await ref.read(messageProvider).sendMediaMessage(
            mediaUrl: url,
            mediaType: mediaType,
            caption: caption,
            replyToMessageId: replyToMessageId,
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

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Microphone permission is required to record voice notes.')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordPath = path;
        _recordDurationSeconds = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordDurationSeconds++;
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordTimer?.cancel();
      await _audioRecorder.stop();
      if (_recordPath != null) {
        final file = File(_recordPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      setState(() {
        _isRecording = false;
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
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;

      final dir = await getTemporaryDirectory();
      final localCopy = File('${dir.path}/local_voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.copy(localCopy.path);

      _sendVoiceNoteFireAndForget(localCopy, file);
    } catch (e) {
      debugPrint('Error stopping and sending recording: $e');
    }
  }

  void _sendVoiceNoteFireAndForget(File localFile, File tempFile) {
    setState(() => _isSendingMedia = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    () async {
      try {
        final folder = 'chat-media/audio';
        final url = await StorageService.uploadFile(
          file: tempFile,
          folder: folder,
          contentType: 'audio/mp4',
          extension: 'm4a',
        );

        final filename = Uri.parse(url).pathSegments.last;
        final docsDir = await getApplicationDocumentsDirectory();
        final voiceNotesDir = Directory('${docsDir.path}/voice_notes');
        if (!await voiceNotesDir.exists()) {
          await voiceNotesDir.create(recursive: true);
        }
        final finalLocalFile = File('${voiceNotesDir.path}/$filename');
        await localFile.copy(finalLocalFile.path);

        try {
          if (await localFile.exists()) await localFile.delete();
          if (await tempFile.exists()) await tempFile.delete();
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
              icon: LucideIcons.image,
              iconColor: AppTheme.accent,
              iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
              title: 'Photo',
              subtitle: 'Send a photo from gallery',
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            const SizedBox(height: 8),
            _MediaOption(
              icon: LucideIcons.video,
              iconColor: AppTheme.accent,
              iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
              title: 'Video',
              subtitle: 'Send a video (max 15s)',
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

    // Set initial scroll position when messages are first loaded
    if (!msgProv.isLoading && msgProv.messages.isNotEmpty && !_hasSetInitialScroll) {
      _hasSetInitialScroll = true;
      final unreadIndex = msgProv.messages.indexWhere((m) => m.senderId != userId && !m.isRead);
      if (unreadIndex != -1) {
        _firstUnreadMessageId = msgProv.messages[unreadIndex].id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToMessage(_firstUnreadMessageId!);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    }

    final blockProv = ref.watch(blockProvider);
    final otherUserId = widget.conversation.otherUserId;
    final isBlocked = blockProv.isUserBlocked(otherUserId);

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
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
          : AppTheme.glassAppBar(
              context: context,
              title: Row(
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
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.ellipsis, size: 20),
                  onSelected: (value) => _handleMenuAction(value, otherUserId, isBlocked),
                  itemBuilder: (context) => [
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
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                msgProv.isLoading && msgProv.messages.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            MessageBubbleSkeleton(isMe: false),
                            SizedBox(height: 8),
                            MessageBubbleSkeleton(isMe: true),
                            SizedBox(height: 8),
                            MessageBubbleSkeleton(isMe: false),
                            SizedBox(height: 8),
                            MessageBubbleSkeleton(isMe: true),
                          ],
                        ),
                      )
                    : msgProv.messages.isEmpty
                        ? const Center(
                            child: Text('Start a conversation',
                                style: TextStyle(color: AppTheme.mutedSteel)),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(16),
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
                                onLongPress: () => isMe ? _enterSelectionMode(msg.id) : null,
                                onTap: () {
                                  if (_isSelectionMode && isMe) {
                                    _toggleSelection(msg.id);
                                  }
                                },
                                onSwipeReply: () => _setReplyTo(msg),
                                onReplyTap: msg.isReply ? () => _scrollToMessage(msg.replyToMessageId!) : null,
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
                                              color: AppTheme.accent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'Unread Messages',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.accent,
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
                          ),
                if (_showScrollDownButton)
                  Positioned(
                    bottom: 16,
                    right: 16,
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
              onRemove: _clearReply,
            ),
          if (_productReference != null)
            _ProductReferenceCard(
              reference: _productReference!,
              onRemove: _removeReference,
            ),
          // Media preview
          if (_pendingMediaList.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pendingMediaList.length,
                      itemExtent: 82,
                      itemBuilder: (context, idx) {
                        final file = _pendingMediaList[idx];
                        final isVideo = _pendingIsVideoList[idx];
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 70,
                          height: 70,
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isVideo
                                    ? Container(
                                        width: 70,
                                        height: 70,
                                        color: AppTheme.charcoalInk,
                                        child: const Center(
                                          child: Icon(LucideIcons.play, size: 20, color: Colors.white),
                                        ),
                                      )
                                    : Image.file(
                                        file,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
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
                    foregroundColor: AppTheme.accent,
                    onPressed: _pickMedia,
                  ),
                ],
              ),
            ),
          ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
              child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              border: const Border(top: BorderSide(color: AppTheme.glassBorder)),
            ),
            child: SafeArea(
              child: _isRecording
                  ? Row(
                      children: [
                        ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.trash2, color: AppTheme.destructive),
                          onPressed: _cancelRecording,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.destructive.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const _BlinkingRedDot(),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(_recordDurationSeconds),
                                  style: const TextStyle(
                                    color: AppTheme.destructive,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Center(
                                    child: _VoiceRecordingWave(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.send),
                          foregroundColor: AppTheme.accent,
                          onPressed: _stopAndSendRecording,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.paperclip),
                          foregroundColor: AppTheme.mutedSteel,
                          onPressed: _isSendingMedia ? null : _pickMedia,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ShadInput(
                            controller: _messageCtrl,
                            focusNode: _messageFocusNode,
                            placeholder: Text(_pendingMediaList.isNotEmpty ? 'Add a caption...' : 'Type a message...'),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            trailing: ShadIconButton.ghost(
                              icon: const Icon(LucideIcons.smile, size: 20),
                              foregroundColor: AppTheme.mutedSteel,
                              onPressed: _openGifPicker,
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
                              return const SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }

                            if (hasInput) {
                              return ShadIconButton.ghost(
                                icon: const Icon(LucideIcons.send),
                                foregroundColor: AppTheme.accent,
                                onPressed: _sendMessage,
                              );
                            } else {
                              return ShadIconButton.ghost(
                                icon: const Icon(LucideIcons.mic),
                                foregroundColor: AppTheme.mutedSteel,
                                onPressed: _startRecording,
                              );
                            }
                          },
                        ),
                      ],
                    ),
            ),
              ),
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
  final VoidCallback onRemove;

  const _ReplyPreviewCard({
    required this.message,
    required this.currentUserId,
    required this.otherUserName,
    this.otherUserVerified = false,
    this.otherBusinessName = '',
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: AppTheme.pureSurface,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.warmMist,
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: AppTheme.accent, width: 3),
          ),
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
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
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
      ),
    );
  }
}

class _ProductReferenceCard extends StatelessWidget {
  final Map<String, dynamic> reference;
  final VoidCallback onRemove;

  const _ProductReferenceCard({
    required this.reference,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = reference['image_url'] as String?;
    final title = reference['title'] as String? ?? '';
    final price = (reference['price'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.accent,
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
              child: const Icon(LucideIcons.package, color: AppTheme.mutedSteel),
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
                const SizedBox(height: 2),
                Text(
                  'GH\u00a2 ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
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
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onReplyTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHighlighted = false,
    this.onLongPress,
    this.onTap,
    this.onSwipeReply,
    this.onReplyTap,
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
              color: widget.isMe ? Colors.white.withValues(alpha: 0.5) : AppTheme.accent,
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
                      color: widget.isMe ? Colors.white.withValues(alpha: 0.9) : AppTheme.accent,
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
    final hasMedia = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty;
    final hasProduct = msg.productReference != null;
    final hasContent = msg.content.isNotEmpty;
    final isVoice = msg.mediaType == 'voice';

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
                ? AppTheme.accent.withValues(alpha: _highlightAnim.value)
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
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
            // Selection checkmark
            if (widget.isSelectionMode && widget.isMe)
              Positioned(
                right: widget.isMe ? null : -8,
                left: widget.isMe ? -8 : null,
                top: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? AppTheme.accent : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected ? AppTheme.accent : AppTheme.whisperBorder,
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
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? (widget.isMe ? AppTheme.accent.withValues(alpha: 0.8) : AppTheme.pureSurface.withValues(alpha: 0.8))
                      : (widget.isMe ? AppTheme.accent : AppTheme.pureSurface),
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
                    if (msg.isReply) _buildReplyQuote(),
                    if (hasMedia)
                      if (isVoice)
                        _VoiceBubbleContent(message: msg, isMe: widget.isMe)
                      else
                        _MediaBubbleContent(message: msg, isMe: widget.isMe),
                    if (hasProduct)
                      _InlineProductCard(
                        reference: msg.productReference,
                        isMe: widget.isMe,
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
                            color: widget.isMe ? Colors.yellow : AppTheme.accent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: hasMedia ? 10 : 0,
                        right: hasMedia ? 10 : 0,
                        top: 4,
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

class _MediaBubbleContent extends StatelessWidget {
  final dynamic message;
  final bool isMe;

  const _MediaBubbleContent({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl as String;
    final isVideo = message.mediaType == 'video';

    return GestureDetector(
      onTap: () => MediaViewer.open(context, [url], initialIndex: 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isVideo)
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
          ],
        ),
      ),
    );
  }
}

class _InlineProductCard extends StatelessWidget {
  final dynamic reference;
  final bool isMe;

  const _InlineProductCard({required this.reference, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final imageUrl = reference.imageUrl as String?;
    final title = reference.title as String? ?? '';
    final price = (reference.price as num?)?.toDouble() ?? 0;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final productId = reference.productId as String?;

    return GestureDetector(
      onTap: productId != null
          ? () => Navigator.of(context).pushNamed('/product', arguments: productId)
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
                        child: const Icon(LucideIcons.package, size: 20, color: AppTheme.mutedSteel),
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
                          const SizedBox(height: 2),
                          Text(
                            'GH\u00a2 ${price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMe ? Colors.white.withValues(alpha: 0.9) : AppTheme.accent,
                            ),
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
                        LucideIcons.externalLink,
                        size: 11,
                        color: isMe ? Colors.white.withValues(alpha: 0.7) : AppTheme.accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'View Product',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white.withValues(alpha: 0.7) : AppTheme.accent,
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
  const _BlinkingRedDot();

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
    )..repeat(reverse: true);
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

class _VoiceBubbleContent extends StatefulWidget {
  final Message message;
  final bool isMe;

  const _VoiceBubbleContent({required this.message, required this.isMe});

  @override
  State<_VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends State<_VoiceBubbleContent> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    _checkIfDownloaded();
  }

  Future<void> _checkIfDownloaded() async {
    try {
      final file = await _getLocalFile();
      final exists = await file.exists();
      if (mounted) {
        setState(() {
          _isDownloaded = exists;
        });
      }
    } catch (_) {}
  }

  Future<File> _getLocalFile() async {
    final uri = Uri.parse(widget.message.mediaUrl!);
    final filename = uri.pathSegments.last;
    final docsDir = await getApplicationDocumentsDirectory();
    final voiceNotesDir = Directory('${docsDir.path}/voice_notes');
    if (!await voiceNotesDir.exists()) {
      await voiceNotesDir.create(recursive: true);
    }
    return File('${voiceNotesDir.path}/$filename');
  }

  Future<void> _downloadVoiceNote() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });

    try {
      final response = await http.get(Uri.parse(widget.message.mediaUrl!));
      if (response.statusCode == 200) {
        final file = await _getLocalFile();
        await file.writeAsBytes(response.bodyBytes);
        
        if (mounted) {
          setState(() {
            _isDownloaded = true;
            _isDownloading = false;
          });
        }

        // Delete from R2 storage immediately
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
        ShadToaster.of(context).show(
          ShadToast(title: Text('Failed to download voice note: $e')),
        );
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

    final file = await _getLocalFile();
    await player.setSource(DeviceFileSource(file.path));
    
    _player = player;
  }

  Future<void> _togglePlay() async {
    try {
      if (!_isDownloaded) {
        await _downloadVoiceNote();
        return;
      }

      await _initPlayer();

      if (_isPlaying) {
        await _player?.pause();
      } else {
        await _player?.resume();
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
    final accentColor = widget.isMe ? Colors.white : AppTheme.accent;
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
                      activeTrackColor: widget.isMe ? Colors.white : AppTheme.accent,
                      inactiveTrackColor: widget.isMe ? Colors.white38 : AppTheme.whisperBorder,
                      thumbColor: widget.isMe ? Colors.white : AppTheme.accent,
                      overlayColor: widget.isMe ? Colors.white12 : AppTheme.accent.withValues(alpha: 0.1),
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
  const _VoiceRecordingWave();

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
    )..repeat();
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
                color: AppTheme.destructive.withValues(alpha: 0.8),
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
  final File file;
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
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
        });
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
