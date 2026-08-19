import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../providers/providers.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../models/notification_model.dart';
import '../../models/message_model.dart';
import '../messages/messages_screen.dart';
import '../../widgets/skeleton.dart';
import '../seller/seller_orders_screen.dart';

enum NotificationFilter {
  all,
  unread,
  orders,
  wallet,
  chats,
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  final ScrollController _scrollController = ScrollController();
  final _filterPopoverController = ShadPopoverController();
  RealtimeChannel? _notificationsChannel;

  // Search & Filter state
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  NotificationFilter _selectedFilter = NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToRealtime();
    _scrollController.addListener(_onScroll);
  }

  void _subscribeToRealtime() {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    _notificationsChannel = SupabaseService.client
        .channel('notifications-screen:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            // Reset and reload on any change
            _page = 0;
            _hasMore = true;
            _loadNotifications();
          },
        );
    _notificationsChannel!.subscribe();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _filterPopoverController.dispose();
    if (_notificationsChannel != null) {
      SupabaseService.client.removeChannel(_notificationsChannel!);
    }
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.8 &&
        _hasMore &&
        !_isLoadingMore) {
      setState(() => _page++);
      _loadMore();
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final typeFilter = _typeForFilter(_selectedFilter);
      final notifications = await NotificationService.getNotifications(
        offset: 0,
        type: typeFilter,
        isRead: _selectedFilter == NotificationFilter.unread ? false : null,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _hasMore = notifications.length >= 20;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final typeFilter = _typeForFilter(_selectedFilter);
      final more = await NotificationService.getNotifications(
        offset: _page * 20,
        type: typeFilter,
        isRead: _selectedFilter == NotificationFilter.unread ? false : null,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (mounted) {
        setState(() {
          _notifications.addAll(more);
          _hasMore = more.length >= 20;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMore = false);
  }

  String? _typeForFilter(NotificationFilter filter) {
    switch (filter) {
      case NotificationFilter.all:
      case NotificationFilter.unread:
        return null;
      case NotificationFilter.orders:
        return 'order';
      case NotificationFilter.wallet:
        return 'payment';
      case NotificationFilter.chats:
        return 'message';
    }
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllAsRead();
    setState(() {
      _notifications = _notifications.map((n) {
        return AppNotification(
          id: n.id,
          userId: n.userId,
          title: n.title,
          body: n.body,
          type: n.type,
          referenceId: n.referenceId,
          data: n.data,
          isRead: true,
          createdAt: n.createdAt,
        );
      }).toList();
    });
  }

  Widget _buildFilterItem({
    required NotificationFilter filter,
    required IconData icon,
    required String label,
  }) {
    final theme = ShadTheme.of(context);
    final isSelected = _selectedFilter == filter;
    final popoverForeground = theme.colorScheme.popoverForeground;
    final textColor = isSelected ? AppTheme.accent : popoverForeground;
    final iconColor = isSelected ? AppTheme.accent : theme.colorScheme.mutedForeground;

    return InkWell(
      onTap: () {
        _filterPopoverController.hide();
        setState(() {
          _selectedFilter = filter;
        });
        _page = 0;
        _hasMore = true;
        _loadNotifications();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Notifications')),
        body: const Center(child: Text('Sign in to view notifications')),
      );
    }

    final filteredNotifications = _notifications;

    final appBarTitle = _isSearching
        ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search notifications...',
              border: InputBorder.none,
              hintStyle: TextStyle(color: AppTheme.mutedSteel, fontSize: 15),
            ),
            style: const TextStyle(fontSize: 16, color: AppTheme.charcoalInk),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim();
              });
              _page = 0;
              _hasMore = true;
              _loadNotifications();
            },
          )
        : const Text('Notifications');

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: appBarTitle,
        actions: [
          ShadIconButton.ghost(
            icon: Icon(
              _isSearching ? LucideIcons.x : LucideIcons.search,
              color: AppTheme.mutedSteel,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
              if (!_isSearching) {
                _page = 0;
                _hasMore = true;
                _loadNotifications();
              }
            },
          ),
          ShadPopover(
            controller: _filterPopoverController,
            anchor: const ShadAnchor(
              childAlignment: Alignment.topRight,
              overlayAlignment: Alignment.bottomRight,
              offset: Offset(0, 8),
            ),
            padding: const EdgeInsets.all(8),
            popover: (context) => SizedBox(
              width: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterItem(
                    filter: NotificationFilter.all,
                    icon: LucideIcons.bell,
                    label: 'All',
                  ),
                  _buildFilterItem(
                    filter: NotificationFilter.unread,
                    icon: LucideIcons.mail,
                    label: 'Unread Only',
                  ),
                  _buildFilterItem(
                    filter: NotificationFilter.orders,
                    icon: LucideIcons.shoppingBag,
                    label: 'Orders & Deliveries',
                  ),
                  _buildFilterItem(
                    filter: NotificationFilter.wallet,
                    icon: LucideIcons.wallet,
                    label: 'Transactions',
                  ),
                  _buildFilterItem(
                    filter: NotificationFilter.chats,
                    icon: LucideIcons.messageSquare,
                    label: 'Chats',
                  ),
                ],
              ),
            ),
            child: GestureDetector(
              onTap: _filterPopoverController.toggle,
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Icon(
                    LucideIcons.slidersHorizontal,
                    color: AppTheme.mutedSteel,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          if (!_isSearching && filteredNotifications.any((n) => !n.isRead))
            ShadButton.ghost(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          Builder(
            builder: (context) {
              final cartCount = ref.watch(cartProvider).itemCount;
              return ShadIconButton.ghost(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      LucideIcons.shoppingCart,
                      color: cartCount > 0 ? AppTheme.accent : AppTheme.mutedSteel,
                    ),
                    if (cartCount > 0)
                      Positioned(
                        top: -4,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.destructive,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          alignment: Alignment.center,
                          child: Text(
                            '$cartCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () => Navigator.of(context).pushNamed('/cart'),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight),
              child: const ListSkeleton(count: 8),
            )
          : filteredNotifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight,
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      context.rw(8),
                      MediaQuery.of(context).padding.top + kToolbarHeight + context.rh(8),
                      context.rw(8),
                      context.rh(8),
                    ),
                    itemCount: filteredNotifications.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, indent: context.rw(16), endIndent: context.rw(16)),
                    itemBuilder: (context, index) {
                      if (index == filteredNotifications.length) {
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
                      final notification = filteredNotifications[index];
                      return GestureDetector(
                        onTap: () {
                          // Mark as read
                          if (!notification.isRead) {
                            NotificationService.markAsRead(notification.id);
                            setState(() {
                              final idx = _notifications.indexOf(notification);
                              if (idx != -1) {
                                _notifications[idx] = AppNotification(
                                  id: notification.id,
                                  userId: notification.userId,
                                  title: notification.title,
                                  body: notification.body,
                                  type: notification.type,
                                  referenceId: notification.referenceId,
                                  data: notification.data,
                                  isRead: true,
                                  createdAt: notification.createdAt,
                                );
                              }
                            });
                          }
                          // Navigate
                          _navigateToNotification(notification);
                        },
                        child: Container(
                          padding: context.rPadding(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: notification.isRead ? null : AppTheme.accent.withValues(alpha: 0.03),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    padding: context.rAll(8),
                                    decoration: BoxDecoration(
                                      color: _colorForType(notification.type).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(context.rr(10)),
                                    ),
                                    child: Icon(
                                      _iconForType(notification.type),
                                      color: _colorForType(notification.type),
                                      size: context.ri(20),
                                    ),
                                  ),
                                  if (!notification.isRead)
                                    Positioned(
                                      top: 0, right: 0,
                                      child: Container(
                                        width: context.rw(10),
                                        height: context.rh(10),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(width: context.rw(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatCurrencySymbol(notification.title),
                                      style: TextStyle(
                                        fontWeight: notification.isRead
                                            ? FontWeight.normal
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    if (notification.body != null)
                                      Text(
                                        _formatCurrencySymbol(notification.body!),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: context.rsp(13),
                                          color: AppTheme.mutedSteel,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _timeAgo(notification.createdAt),
                                    style: TextStyle(
                                      fontSize: context.rsp(11),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                  if (!notification.isRead) ...[
                                    SizedBox(height: context.rh(6)),
                                    Container(
                                      padding: context.rPadding(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(context.rr(4)),
                                      ),
                                      child: Text(
                                        'New',
                                        style: TextStyle(
                                          fontSize: context.rsp(9),
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.accent,
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
                    },
                  ),
                ),
    );
  }

  void _navigateToNotification(AppNotification notification) {
    final data = notification.data;
    switch (notification.type) {
      case 'order':
      case 'delivery':
      case 'delivery_approved':
        final orderId = data?['order_id'] as String?;
        if (orderId != null) {
          if (notification.title.toLowerCase().contains('new order') ||
              notification.title.toLowerCase().contains('received')) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SellerOrdersScreen()),
            );
          } else {
            Navigator.of(context).pushNamed('/order-detail', arguments: orderId);
          }
        }
        break;
      case 'message':
      case 'new_message':
        final conversationId = data?['conversation_id'] as String?;
        if (conversationId != null) {
          _openConversationFromNotification(conversationId);
        } else {
          Navigator.of(context).pushNamed('/messages');
        }
        break;
      case 'new_product':
        final productId = data?['product_id'] as String?;
        if (productId != null) {
          Navigator.of(context).pushNamed('/product', arguments: productId);
        }
        break;
      case 'new_follower':
        final followerId = data?['follower_id'] as String?;
        if (followerId != null) {
          Navigator.of(context).pushNamed('/business-profile', arguments: followerId);
        }
        break;
      case 'verification_approved':
      case 'verification_rejected':
        Navigator.of(context).pushNamed('/seller-dashboard');
        break;
      case 'transfer_received':
      case 'transfer_sent':
      case 'deposit':
      case 'withdrawal':
        Navigator.of(context).pushNamed('/wallet');
        break;
      case 'review':
        // Navigate to the product that was reviewed
        final productId = data?['product_id'] as String?;
        if (productId != null) {
          Navigator.of(context).pushNamed('/product', arguments: productId);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _openConversationFromNotification(String conversationId) async {
    final provider = ref.read(messageProvider);
    
    // Ensure conversations are loaded
    if (provider.conversations.isEmpty) {
      await provider.loadConversations(silent: true);
    }
    
    // Try to find the conversation
    Conversation? conv;
    for (final c in provider.conversations) {
      if (c.id == conversationId) {
        conv = c;
        break;
      }
    }
    
    // If not found in the loaded list, let's try to reload conversations once more
    if (conv == null) {
      await provider.loadConversations(silent: true);
      for (final c in provider.conversations) {
        if (c.id == conversationId) {
          conv = c;
          break;
        }
      }
    }
    
    // If still not found, fetch from Supabase directly to construct a Conversation object
    if (conv == null) {
      try {
        final uid = SupabaseService.auth.currentUser?.id;
        if (uid != null) {
          final json = await SupabaseService.client
              .from('conversations')
              .select('''
                id,
                participant1_id,
                participant2_id,
                last_message,
                last_message_at,
                user1:users!conversations_participant1_id_fkey(full_name, avatar_url),
                user2:users!conversations_participant2_id_fkey(full_name, avatar_url)
              ''')
              .eq('id', conversationId)
              .single();
          
          final isFirst = json['participant1_id'] == uid;
          final otherProfile = isFirst
              ? json['user2'] as Map<String, dynamic>?
              : json['user1'] as Map<String, dynamic>?;
          final otherUserId = isFirst
              ? json['participant2_id'] as String
              : json['participant1_id'] as String;
          
          conv = Conversation(
            id: conversationId,
            otherUserId: otherUserId,
            otherUserName: otherProfile?['full_name'] as String?,
            otherUserAvatar: otherProfile?['avatar_url'] as String?,
            lastMessage: json['last_message'] as String?,
            lastMessageAt: json['last_message_at'] != null
                ? DateTime.parse(json['last_message_at'] as String)
                : null,
            unreadCount: 0,
          );
        }
      } catch (e) {
        debugPrint('Error fetching conversation from notification: $e');
      }
    }
    
    if (conv != null) {
      provider.setActiveConversation(conv);
      provider.loadMessages(conv.id); // ignore: unawaited_futures
      if (mounted) {
        Navigator.of(context).push( // ignore: unawaited_futures
          MaterialPageRoute(
            builder: (_) => ConversationScreen(conversation: conv),
          ),
        );
      }
    } else {
      if (mounted) {
        Navigator.of(context).pushNamed('/messages'); // ignore: unawaited_futures
      }
    }
  }

  Widget _buildEmptyState() {
    final isFilteringOrSearching = _searchQuery.isNotEmpty || _selectedFilter != NotificationFilter.all;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFilteringOrSearching ? LucideIcons.search : LucideIcons.bell,
            size: context.ri(64),
            color: AppTheme.whisperBorder,
          ),
          SizedBox(height: context.rh(16)),
          Text(
            isFilteringOrSearching ? 'No matching notifications' : 'No notifications yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (isFilteringOrSearching) ...[
            SizedBox(height: context.rh(8)),
            Text(
              'Try clearing your search or filter options.',
              style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
            ),
          ],
        ],
      ),
    );
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'transfer_sent':
      case 'withdrawal':
        return AppTheme.destructive;
      case 'transfer_received':
      case 'deposit':
        return AppTheme.successMoss;
      case 'verification_approved':
        return AppTheme.successMoss;
      case 'verification_rejected':
        return AppTheme.destructive;
      case 'delivery':
      case 'delivery_approved':
        return AppTheme.accent;
      case 'message':
      case 'new_message':
        return AppTheme.accent;
      default:
        return AppTheme.mutedSteel;
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'order':
        return LucideIcons.shoppingBag;
      case 'message':
      case 'new_message':
        return LucideIcons.messageSquare;
      case 'payment':
      case 'transfer_sent':
      case 'transfer_received':
      case 'deposit':
      case 'withdrawal':
        return LucideIcons.wallet;
      case 'review':
        return LucideIcons.star;
      case 'verification':
      case 'verification_approved':
      case 'verification_rejected':
        return LucideIcons.shieldCheck;
      case 'delivery':
      case 'delivery_approved':
        return LucideIcons.truck;
      default:
        return LucideIcons.bell;
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  String _formatCurrencySymbol(String text) {
    return text
        .replaceAll(r'GH\u00a2', 'GH₵')
        .replaceAll(r'GH\\u00a2', 'GH₵')
        .replaceAll(r'\u00a2', '₵')
        .replaceAll(r'\\u00a2', '₵')
        .replaceAll('GH¢', 'GH₵')
        .replaceAll('¢', '₵');
  }
}
