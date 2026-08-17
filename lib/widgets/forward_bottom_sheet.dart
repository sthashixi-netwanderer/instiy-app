import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/message_model.dart';
import '../services/message_service.dart';
import '../utils/responsive.dart';
import 'verification_badge.dart';

/// Telegram-style forward bottom sheet that shows recent conversations
/// so the user can forward a media file to another chat.
class ForwardBottomSheet extends StatefulWidget {
  final String mediaUrl;
  final String mediaType;
  final String? thumbnailUrl;

  const ForwardBottomSheet({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
  });

  /// Shows the forward bottom sheet and returns the target conversation
  /// if the user forwarded, or null if cancelled.
  static Future<bool> show(
    BuildContext context, {
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardBottomSheet(
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
      ),
    );
    return result ?? false;
  }

  @override
  State<ForwardBottomSheet> createState() => _ForwardBottomSheetState();
}

class _ForwardBottomSheetState extends State<ForwardBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Conversation> _conversations = [];
  List<Conversation> _filtered = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _sentToId;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = List.from(_conversations);
      } else {
        _filtered = _conversations
            .where((c) => c.displayName.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _loadConversations() async {
    try {
      final all = await MessageService.getConversations(offset: 0, limit: 30);
      if (mounted) {
        setState(() {
          _conversations = all;
          _filtered = List.from(all);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forwardTo(Conversation conversation) async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      final mediaType = _inferMediaType(widget.mediaUrl, widget.mediaType);
      // For videos, combine videoUrl|thumbnailUrl as stored in the database
      final String storedUrl;
      if (mediaType == 'video' &&
          widget.thumbnailUrl != null &&
          widget.thumbnailUrl!.isNotEmpty) {
        storedUrl = '${widget.mediaUrl}|${widget.thumbnailUrl}';
      } else {
        storedUrl = widget.mediaUrl;
      }
      await MessageService.sendMediaMessage(
        conversationId: conversation.id,
        mediaUrl: storedUrl,
        mediaType: mediaType,
        caption: 'Forwarded',
      );

      if (mounted) {
        setState(() {
          _sentToId = conversation.id;
          _isSending = false;
        });

        // Show success toast
        ShadToaster.of(context).show(
          ShadToast(title: Text('Forwarded to ${conversation.displayName}')),
        );

        // Close sheet after brief delay so user sees the confirmation
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Failed to forward'),
            description: Text('Please try again'),
          ),
        );
      }
    }
  }

  String _inferMediaType(String url, String declared) {
    if (declared == 'video' || declared == 'image' || declared == 'gif') {
      return declared;
    }
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi')) {
      return 'video';
    }
    return 'image';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.55 + bottomPadding,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.rw(16),
              vertical: context.rh(12),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.forward,
                  size: context.ri(20),
                  color: AppTheme.accent,
                ),
                SizedBox(width: context.rw(8)),
                Text(
                  'Forward to...',
                  style: TextStyle(
                    fontSize: context.rsp(18),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                hintStyle: TextStyle(
                  fontSize: context.rsp(14),
                  color: AppTheme.mutedSteel,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: context.ri(18),
                  color: AppTheme.mutedSteel,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          LucideIcons.x,
                          size: context.ri(16),
                          color: AppTheme.mutedSteel,
                        ),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.warmMist,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: context.rw(12),
                  vertical: context.rh(10),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.rr(12)),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(fontSize: context.rsp(14)),
            ),
          ),

          SizedBox(height: context.rh(8)),

          // Conversation list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isNotEmpty
                          ? 'No conversations found'
                          : 'No conversations',
                      style: TextStyle(
                        color: AppTheme.mutedSteel,
                        fontSize: context.rsp(14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final conv = _filtered[index];
                      final isSent = _sentToId == conv.id;

                      return _ForwardConversationTile(
                        conversation: conv,
                        isSending: _isSending && isSent,
                        onTap: () => _forwardTo(conv),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ForwardConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSending;
  final VoidCallback onTap;

  const _ForwardConversationTile({
    required this.conversation,
    required this.isSending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isSending ? null : onTap,
      child: Padding(
        padding: context.rPadding(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            ShadAvatar(
              (conversation.otherUserAvatar != null &&
                      conversation.otherUserAvatar!.isNotEmpty)
                  ? conversation.otherUserAvatar!
                  : null,
              size: Size(context.rw(46), context.rh(46)),
              backgroundColor: AppTheme.accent,
              placeholder: Text(
                conversation.displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: context.rw(12)),

            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conversation.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: context.rsp(15),
                          ),
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
                    conversation.lastMessage ?? '',
                    style: TextStyle(
                      color: AppTheme.mutedSteel,
                      fontSize: context.rsp(13),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Sending indicator or forward icon
            if (isSending)
              SizedBox(
                width: context.rw(20),
                height: context.rh(20),
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent,
                ),
              )
            else
              Icon(
                LucideIcons.forward,
                size: context.ri(18),
                color: AppTheme.mutedSteel,
              ),
          ],
        ),
      ),
    );
  }
}
