import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/follow_service.dart';
import '../../services/block_service.dart';
import '../../widgets/verification_badge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/responsive.dart';

class FollowingScreen extends ConsumerStatefulWidget {
  final int initialTab; // 0 = followers, 1 = following

  const FollowingScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends ConsumerState<FollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  bool _isLoadingFollowers = true;
  bool _isLoadingFollowing = true;
  String _searchQuery = '';
  Set<String> _blockedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    // Blocks changed anywhere in the app affect who shows in these lists
    ref.listenManual(blockProvider, (previous, next) {
      _loadBlockedIds();
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    await Future.wait([
      _loadFollowers(userId),
      _loadFollowing(userId),
      _loadBlockedIds(),
    ]);
  }

  Future<void> _loadFollowers(String userId) async {
    setState(() => _isLoadingFollowers = true);
    try {
      // Get users who follow the current user (followers of my store)
      final followers = await FollowService.getFollowersList(userId);
      if (mounted) {
        setState(() {
          _followers = followers;
          _isLoadingFollowers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFollowers = false);
      }
    }
  }

  Future<void> _loadFollowing(String userId) async {
    setState(() => _isLoadingFollowing = true);
    try {
      final following = await FollowService.getFollowingList(userId);
      if (mounted) {
        setState(() {
          _following = following;
          _isLoadingFollowing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFollowing = false);
      }
    }
  }

  Future<void> _loadBlockedIds() async {
    final ids = await BlockService.getBlockedUserIds();
    if (mounted) setState(() => _blockedIds = ids);
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((u) {
      final name = (u['name'] as String? ?? '').toLowerCase();
      final uni = (u['university'] as String? ?? '').toLowerCase();
      return name.contains(q) || uni.contains(q);
    }).toList();
  }

  Future<void> _toggleBlock(String userId) async {
    final isBlocked = _blockedIds.contains(userId);
    if (isBlocked) {
      await BlockService.unblockUser(userId);
      setState(() => _blockedIds.remove(userId));
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('User unblocked')),
        );
      }
    } else {
final confirmed = await AppTheme.showGlassDialog<bool>(
  context: context,
  title: const Text('Block this user?'),
  description: const Text(
    'They won\'t be able to message you. You can unblock them later.',
  ),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(false),
      child: const Text('Cancel'),
    ),
    ShadButton.destructive(
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text('Block'),
    ),
  ],
);
      if (confirmed == true) {
        await BlockService.blockUser(userId);
        setState(() => _blockedIds.add(userId));
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('User blocked')),
          );
        }
      }
    }
  }

  Future<void> _toggleFollow(String sellerId, bool isCurrentlyFollowing) async {
    try {
      if (isCurrentlyFollowing) {
        await FollowService.unfollow(sellerId);
      } else {
        await FollowService.follow(sellerId);
      }
      // Refresh the lists
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) {
        await _loadFollowing(userId);
        await _loadFollowers(userId);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Following'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.mutedSteel,
          indicatorColor: AppTheme.accent,
          tabs: [
            Tab(text: 'Followers (${_followers.length})'),
            Tab(text: 'Following (${_following.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.rw(16),
              MediaQuery.paddingOf(context).top + kToolbarHeight + kTextTabBarHeight + context.rh(12),
              context.rw(16),
              context.rh(8),
            ),
            child: ShadInput(
              controller: _searchController,
              placeholder: const Text('Search...'),
              leading: Padding(
                padding: EdgeInsets.only(left: context.rw(8)),
                child: Icon(LucideIcons.search, size: context.ri(18), color: AppTheme.mutedSteel),
              ),
              trailing: _searchController.text.isNotEmpty
                  ? ShadIconButton.ghost(
                      icon: Icon(LucideIcons.x, size: context.ri(16), color: AppTheme.mutedSteel),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Tabs content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(
                  users: _filteredList(_followers),
                  isLoading: _isLoadingFollowers,
                  emptyMessage: 'No followers yet',
                  showFollowBack: true,
                ),
                _buildUserList(
                  users: _filteredList(_following),
                  isLoading: _isLoadingFollowing,
                  emptyMessage: 'You\'re not following anyone yet',
                  showFollowBack: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList({
    required List<Map<String, dynamic>> users,
    required bool isLoading,
    required String emptyMessage,
    required bool showFollowBack,
  }) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    if (users.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
            Center(
              child: Column(
                children: [
                  Icon(LucideIcons.users, size: context.ri(48), color: AppTheme.mutedSteel.withValues(alpha: 0.4)),
                  SizedBox(height: context.rh(12)),
                  Text(emptyMessage, style: const TextStyle(color: AppTheme.mutedSteel)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(8)),
      itemCount: users.length,
      separatorBuilder: (context, index) => SizedBox(height: context.rh(8)),
      itemBuilder: (context, index) {
        final user = users[index];
        final userId = user['id'] as String;
        final name = user['name'] as String? ?? 'User';
        final avatarUrl = user['avatar_url'] as String?;
        final university = user['university'] as String?;
        final isVerified = user['is_verified'] as bool? ?? false;
        final isBlocked = _blockedIds.contains(userId);

        // Check if current user is following this person
        final isFollowing = _following.any((f) => f['id'] == userId);
        final currentUserId = ref.read(authProvider).user?.id;
        final isSelf = userId == currentUserId;

        return Container(
          padding: context.rAll(12),
          decoration: BoxDecoration(
            color: AppTheme.glassSurfaceLight,
            borderRadius: BorderRadius.circular(context.rr(12)),
            border: Border.all(
              color: isBlocked ? AppTheme.destructive.withValues(alpha: 0.3) : AppTheme.glassBorder,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: context.rw(22),
                backgroundColor: AppTheme.warmMist,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.charcoalInk,
                        ),
                      )
                    : null,
              ),
              SizedBox(width: context.rw(12)),
              // Name + university
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.rsp(14),
                              color: isBlocked
                                  ? AppTheme.mutedSteel
                                  : AppTheme.charcoalInk,
                              decoration: isBlocked ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          SizedBox(width: context.rw(4)),
                          const VerificationBadge(size: 14),
                        ],
                        if (isBlocked) ...[
                          SizedBox(width: context.rw(6)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(1)),
                            decoration: BoxDecoration(
                              color: AppTheme.destructive.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(context.rr(4)),
                            ),
                            child: Text(
                              'Blocked',
                              style: TextStyle(fontSize: context.rsp(10), color: AppTheme.destructive, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (university != null && university.isNotEmpty)
                      Text(
                        university,
                        style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Action buttons
              if (!isSelf) ...[
                // Block/Unblock button
                GestureDetector(
                  onTap: () => _toggleBlock(userId),
                  child: Container(
                    padding: context.rAll(6),
                    decoration: BoxDecoration(
                      color: isBlocked
                          ? AppTheme.destructive.withValues(alpha: 0.1)
                          : AppTheme.warmMist,
                      borderRadius: BorderRadius.circular(context.rr(8)),
                    ),
                    child: Icon(
                      isBlocked ? LucideIcons.shieldCheck : LucideIcons.shield,
                      size: context.ri(16),
                      color: isBlocked ? AppTheme.destructive : AppTheme.mutedSteel,
                    ),
                  ),
                ),
                SizedBox(width: context.rw(8)),
                // Unfollow/Follow back buttons
                if (!isBlocked) ...[
                  if (!showFollowBack)
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: () => _toggleFollow(userId, true),
                      child: const Text('Unfollow'),
                    )
                  else if (!isFollowing)
                    ShadButton(
                      size: ShadButtonSize.sm,
                      onPressed: () => _toggleFollow(userId, false),
                      child: const Text('Follow back'),
                    )
                  else
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: () => _toggleFollow(userId, true),
                      child: const Text('Unfollow'),
                    ),
                ],
              ],
            ],
          ),
        );
      },
      ),
    );
  }
}
