import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../models/message_model.dart';
import '../../providers/providers.dart';
import '../../services/message_service.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/skeleton.dart';

class BlockedChatsScreen extends ConsumerStatefulWidget {
  const BlockedChatsScreen({super.key});

  @override
  ConsumerState<BlockedChatsScreen> createState() => _BlockedChatsScreenState();
}

class _BlockedChatsScreenState extends ConsumerState<BlockedChatsScreen> {
  List<Conversation> _blockedConversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBlocked());
  }

  Future<void> _loadBlocked() async {
    setState(() => _isLoading = true);
    try {
      final allConversations = await MessageService.getConversations(offset: 0, limit: 100);
      final blockProv = ref.read(blockProvider);
      _blockedConversations = allConversations
          .where((c) => blockProv.isUserBlocked(c.otherUserId))
          .toList();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Blocked')),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight),
              child: const ListSkeleton(count: 6))
          : _blockedConversations.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 8, 100),
                  itemCount: _blockedConversations.length,
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (context, index) {
                    final conv = _blockedConversations[index];
                    return _BlockedConversationTile(
                      conversation: conv,
                      onUnblock: () async {
                        await ref.read(blockProvider).unblockUser(conv.otherUserId);
                        setState(() {
                          _blockedConversations.removeWhere((c) => c.id == conv.id);
                        });
                        if (context.mounted) {
                          ShadToaster.of(context).show(ShadToast(title: const Text('User unblocked')));
                        }
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
          Icon(Icons.block, size: context.ri(64), color: Colors.grey[300]),
          SizedBox(height: context.rh(16)),
          Text(
            'No blocked users',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Users you block will appear here.',
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }
}

class _BlockedConversationTile extends StatelessWidget {
  final dynamic conversation;
  final VoidCallback onUnblock;

  const _BlockedConversationTile({
    required this.conversation,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  'Blocked',
                  style: TextStyle(
                    color: AppTheme.mutedSteel,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          ShadButton(
            onPressed: onUnblock,
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}
