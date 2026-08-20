import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../providers/providers.dart';
import '../../providers/message_provider.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/skeleton.dart';
import 'messages_screen.dart';

class ArchivedChatsScreen extends ConsumerStatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  ConsumerState<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends ConsumerState<ArchivedChatsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messageProvider).loadArchivedConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final msgProv = ref.watch(messageProvider);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Archived')),
      body: msgProv.isLoadingArchived && msgProv.archivedConversations.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight),
              child: const ListSkeleton(count: 6))
          : msgProv.archivedConversations.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 8, 100),
                  itemCount: msgProv.archivedConversations.length,
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (context, index) {
                    final conv = msgProv.archivedConversations[index];
                    return _ArchivedConversationTile(
                      conversation: conv,
                      onTap: () => _openConversation(context, conv, msgProv),
                      onUnarchive: () {
                        msgProv.unarchiveConversation(conv.id);
                        ShadToaster.of(context).show(ShadToast(title: const Text('Chat unarchived')));
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.archive, size: context.ri(64), color: Colors.grey[300]),
          SizedBox(height: context.rh(16)),
          Text(
            'No archived chats',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Long-press a chat to archive it.',
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
}

class _ArchivedConversationTile extends StatelessWidget {
  final dynamic conversation;
  final VoidCallback onTap;
  final VoidCallback onUnarchive;

  const _ArchivedConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onUnarchive,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () => _showContextMenu(context),
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
                      color: AppTheme.mutedSteel,
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
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.unarchive, color: Colors.orange),
              title: const Text('Unarchive chat'),
              onTap: () {
                Navigator.pop(context);
                onUnarchive();
              },
            ),
          ],
        ),
      ),
    );
  }
}
