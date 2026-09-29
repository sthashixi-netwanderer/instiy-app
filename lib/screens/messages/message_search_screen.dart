import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/app_theme.dart';
import '../../models/message_model.dart';
import '../../providers/providers.dart';
import '../../providers/block_provider.dart';
import '../../services/message_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';
import 'messages_screen.dart';

/// WhatsApp-style chat search: a full-screen page (opened from the Messages
/// app bar) that matches both chat names and message content. Tapping a
/// name match opens that chat; tapping a message match opens the chat the
/// matched message lives in.
class MessageSearchScreen extends ConsumerStatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  ConsumerState<MessageSearchScreen> createState() =>
      _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;

  /// Every non-hidden conversation, paged in once on open so name search
  /// covers the whole chat list (the provider only holds the first page).
  List<Conversation> _allChats = [];
  bool _chatsLoading = true;

  List<Conversation> _nameMatches = [];
  List<_MessageHit> _messageMatches = [];
  bool _searching = false;
  bool _hasQuery = false;
  final Map<String, Conversation> _convById = {};

  @override
  void initState() {
    super.initState();
    _loadAllChats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAllChats() async {
    try {
      final chats = <Conversation>[];
      const pageSize = 20;
      for (var page = 0; page < 10; page++) {
        final batch = await MessageService.getConversations(offset: page * pageSize);
        chats.addAll(batch);
        if (batch.length < pageSize) break;
      }
      if (!mounted) return;
      setState(() {
        _allChats = chats;
        _chatsLoading = false;
        _convById
          ..clear()
          ..addEntries(chats.map((c) => MapEntry(c.id, c)));
      });
    } catch (_) {
      if (mounted) setState(() => _chatsLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _hasQuery = false;
        _searching = false;
        _nameMatches = [];
        _messageMatches = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    final q = query.toLowerCase();
    setState(() => _searching = true);

    final nameMatches = _allChats
        .where((c) => !BlockProvider.instance.isUserBlocked(c.otherUserId))
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList();

    final messageMatches = <_MessageHit>[];
    try {
      final hits = await MessageService.searchMessages(query);
      for (final hit in hits) {
        final convId = hit['conversation_id'] as String?;
        if (convId == null) continue;
        final conv = _convById[convId] ?? await _resolveConversation(convId);
        if (conv == null) continue;
        if (BlockProvider.instance.isUserBlocked(conv.otherUserId)) continue;
        if (nameMatches.any((c) => c.id == conv.id)) continue;
        messageMatches.add(_MessageHit(conversation: conv, row: hit));
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _nameMatches = nameMatches;
      _messageMatches = messageMatches;
      _searching = false;
      _hasQuery = true;
    });
  }

  /// Resolves a conversation for a message hit that isn't in the loaded
  /// chat list (e.g. an archived chat) — cached after the first lookup.
  Future<Conversation?> _resolveConversation(String conversationId) async {
    try {
      final conv = await MessageService.getConversationById(conversationId);
      if (conv != null) {
        _convById[conversationId] = conv;
      }
      return conv;
    } catch (_) {
      return null;
    }
  }

  void _openChat(Conversation conv) {
    final provider = ref.read(messageProvider);
    provider.setActiveConversation(conv);
    provider.loadMessages(conv.id); // ignore: unawaited_futures
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(conversation: conv),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildGlassSearchHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassSearchHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.rw(12), context.rh(8), context.rw(12), context.rh(4)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppTheme.glassBlurLight,
            sigmaY: AppTheme.glassBlurLight,
          ),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: context.rr(16)),
            padding: EdgeInsets.symmetric(
                horizontal: context.rw(4), vertical: context.rw(4)),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(LucideIcons.arrowLeft, size: context.ri(20)),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppTheme.charcoalInk,
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: context.rsp(15),
                      color: AppTheme.charcoalInk,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search chats and messages...',
                      hintStyle: TextStyle(
                        fontSize: context.rsp(15),
                        color: AppTheme.mutedSteel,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(LucideIcons.x, size: context.ri(18)),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    color: AppTheme.mutedSteel,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_chatsLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ListSkeleton(count: 6),
      );
    }
    if (!_hasQuery) {
      return _buildChatList(
        _allChats
            .where((c) => !BlockProvider.instance.isUserBlocked(c.otherUserId))
            .toList(),
        emptyText: 'No chats yet',
      );
    }
    if (_searching) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_nameMatches.isEmpty && _messageMatches.isEmpty) {
      return _buildEmptyResults();
    }
    return ListView(
      padding: EdgeInsets.only(bottom: context.rh(24)),
      children: [
        if (_nameMatches.isNotEmpty) ...[
          _sectionHeader('Chats'),
          for (final conv in _nameMatches)
            _ChatRow(
              key: ValueKey('chat_${conv.id}'),
              conversation: conv,
              onTap: () => _openChat(conv),
            ),
        ],
        if (_messageMatches.isNotEmpty) ...[
          _sectionHeader('Messages'),
          for (final hit in _messageMatches)
            _MessageRow(
              key: ValueKey('msg_${hit.row['id']}'),
              hit: hit,
              onTap: () => _openChat(hit.conversation),
            ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.rw(16), context.rh(14), context.rw(16), context.rh(6)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: context.rsp(12),
          fontWeight: FontWeight.w700,
          color: AppTheme.mutedSteel,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildChatList(List<Conversation> chats,
      {required String emptyText}) {
    if (chats.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            fontSize: context.rsp(14),
            color: AppTheme.mutedSteel,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: context.rh(24)),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final conv = chats[index];
        return _ChatRow(
          key: ValueKey('chat_${conv.id}'),
          conversation: conv,
          onTap: () => _openChat(conv),
          subtitle: conv.lastMessage,
          timestamp: conv.lastMessageAt,
        );
      },
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.rw(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.searchX,
              size: context.ri(44),
              color: AppTheme.mutedSteel.withValues(alpha: 0.4),
            ),
            SizedBox(height: context.rh(12)),
            Text(
              'No chats or messages found',
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Try a different name or keyword.',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageHit {
  final Conversation conversation;
  final Map<String, dynamic> row;

  const _MessageHit({required this.conversation, required this.row});

  String? get _content => row['content'] as String?;

  String get snippet {
    final content = _content?.trim() ?? '';
    if (content.isNotEmpty) return content;
    switch (row['media_type'] as String?) {
      case 'voice':
        return '🎙️ Voice note';
      case 'video':
        return '📹 Video';
      case 'image':
        return '📷 Photo';
      default:
        return 'Sent a message';
    }
  }

  DateTime? get sentAt {
    final raw = row['created_at'] as String?;
    return raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
  }
}

/// Shared row chrome: avatar, name, one-line subtitle and timestamp —
/// mirrors the conversation tile style on the Messages screen.
class _ChatRow extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final String? subtitle;
  final DateTime? timestamp;

  const _ChatRow({
    super.key,
    required this.conversation,
    required this.onTap,
    this.subtitle,
    this.timestamp,
  });

  String _timeLabel(BuildContext context) {
    final time = timestamp;
    if (time == null) return '';
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    return use24
        ? DateFormat('MMM d, HH:mm').format(time)
        : DateFormat('MMM d, h:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final avatar = conversation.otherUserAvatar;
    final hasText = subtitle != null && subtitle!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.rw(16), vertical: context.rh(10)),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: context.rw(46),
                height: context.rw(46),
                child: (avatar != null && avatar.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        memCacheWidth: 128,
                        errorWidget: (_, _, _) => _avatarFallback(context),
                      )
                    : _avatarFallback(context),
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasText ? subtitle! : 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasText
                          ? AppTheme.mutedSteel
                          : AppTheme.mutedSteel.withValues(alpha: 0.5),
                      fontStyle: hasText
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            if (timestamp != null) ...[
              SizedBox(width: context.rw(8)),
              Text(
                _timeLabel(context),
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.mutedSteel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(BuildContext context) {
    return Container(
      color: AppTheme.accent.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        conversation.displayName.isNotEmpty
            ? conversation.displayName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A message keyword hit — the chat it belongs to plus the matched text.
class _MessageRow extends StatelessWidget {
  final _MessageHit hit;
  final VoidCallback onTap;

  const _MessageRow({super.key, required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      conversation: hit.conversation,
      onTap: onTap,
      subtitle: hit.snippet,
      timestamp: hit.sentAt,
    );
  }
}
