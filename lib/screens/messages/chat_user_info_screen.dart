import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../models/message_model.dart';
import '../../models/business_profile_model.dart';
import '../../models/institution_model.dart';
import '../../models/user_model.dart';
import '../../providers/providers.dart';
import '../../services/business_profile_service.dart';
import '../../services/institution_service.dart';
import '../../services/message_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/verification_badge.dart';
import '../seller/business_profile_screen.dart';
import 'report_screen.dart';
import 'chat_background_settings_screen.dart';
import '../../utils/phone_utils.dart';

class ChatUserInfoScreen extends ConsumerStatefulWidget {
  final Conversation conversation;

  const ChatUserInfoScreen({super.key, required this.conversation});

  @override
  ConsumerState<ChatUserInfoScreen> createState() => _ChatUserInfoScreenState();
}

class _ChatUserInfoScreenState extends ConsumerState<ChatUserInfoScreen> {
  BusinessProfile? _businessProfile;
  StoreStats? _storeStats;
  AppUser? _otherUser;
  Institution? _institution;
  List<Message> _mediaMessages = [];
  bool _isLoadingProfile = true;
  bool _isLoadingMedia = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load other user profile, business profile, and media messages in parallel
    await Future.wait([
      _loadOtherUserProfile(),
      _loadBusinessProfile(),
      _loadMediaMessages(),
    ]);
    // Look up institution logo after user profile loads
    if (mounted &&
        _otherUser?.university != null &&
        _otherUser!.university!.isNotEmpty) {
      unawaited(_loadInstitutionLogo(_otherUser!.university!));
    }
  }

  Future<void> _loadOtherUserProfile() async {
    try {
      final user = await AuthService.getUserProfileById(
        widget.conversation.otherUserId,
      );
      if (mounted) {
        setState(() {
          _otherUser = user;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBusinessProfile() async {
    try {
      final profile = await BusinessProfileService.getProfile(
        widget.conversation.otherUserId,
      );
      if (profile != null) {
        final stats = await BusinessProfileService.getStoreStats(
          widget.conversation.otherUserId,
        );
        if (mounted) {
          setState(() {
            _businessProfile = profile;
            _storeStats = stats;
            _isLoadingProfile = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadMediaMessages() async {
    try {
      final messages = await MessageService.getMessages(
        widget.conversation.id,
        offset: 0,
      );
      if (mounted) {
        setState(() {
          _mediaMessages = messages.where((m) => m.mediaUrl != null).toList();
          _isLoadingMedia = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  Future<void> _loadInstitutionLogo(String universityName) async {
    try {
      final institutions = await InstitutionService.getInstitutions();
      final match = institutions.firstWhere(
        (i) => i.name.toLowerCase() == universityName.toLowerCase(),
        orElse: () => Institution(id: '', code: '', name: ''),
      );
      if (mounted && match.id.isNotEmpty) {
        setState(() => _institution = match);
      }
    } catch (_) {}
  }

  void _toggleArchive() async {
    final provider = ref.read(messageProvider);
    if (widget.conversation.isArchived) {
      await provider.unarchiveConversation(widget.conversation.id);
    } else {
      await provider.archiveConversation(widget.conversation.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleBlock() async {
    final blockNotifier = ref.read(blockProvider.notifier);
    final isBlocked = ref
        .read(blockProvider)
        .isUserBlocked(widget.conversation.otherUserId);

    if (isBlocked) {
      unawaited(blockNotifier.unblockUser(widget.conversation.otherUserId));
      if (mounted) {
        ShadToaster.of(
          context,
        ).show(const ShadToast(title: Text('User unblocked')));
      }
    } else {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Block User?'),
          content: Text(
            'Block ${widget.conversation.displayName}? You won\'t receive messages from them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        unawaited(blockNotifier.blockUser(widget.conversation.otherUserId));
        if (mounted) {
          ShadToaster.of(
            context,
          ).show(const ShadToast(title: Text('User blocked')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(messageProvider).conversations;
    final conv = conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
      orElse: () =>
          ref.watch(messageProvider).activeConversation ?? widget.conversation,
    );
    final isBlocked = ref.watch(blockProvider).isUserBlocked(conv.otherUserId);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text(conv.displayName),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
        ),
        children: [
          // Header section
          _buildHeader(conv),
          SizedBox(height: context.rh(16)),

          // Store card (if seller)
          if (!_isLoadingProfile && _businessProfile != null) _buildStoreCard(),

          // Contact info (phone numbers)
          if (_businessProfile != null &&
              _businessProfile!.phoneNumbers.isNotEmpty)
            _buildContactInfo(),

          // Shared media section
          if (!_isLoadingMedia && _mediaMessages.isNotEmpty)
            _buildMediaSection(),

          // Action buttons
          _buildActions(isBlocked),
          SizedBox(height: context.rh(24)),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader(Conversation conv) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: context.rh(32)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar with online indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: conv.otherUserAvatar?.isNotEmpty == true
                    ? () => MediaViewer.open(context, [
                        conv.otherUserAvatar!,
                      ], initialIndex: 0)
                    : null,
                child: ShadAvatar(
                  conv.otherUserAvatar,
                  size: const Size(80, 80),
                  backgroundColor: AppTheme.accent,
                  placeholder: Text(
                    conv.displayName.isNotEmpty
                        ? conv.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                ),
              ),
              if (conv.isOnline)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: context.rh(12)),

          // Name + verification badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  conv.displayName,
                  style: TextStyle(
                    fontSize: context.rsp(20),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.charcoalInk,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (conv.otherUserVerified) ...[
                SizedBox(width: context.rw(4)),
                VerificationBadge(size: context.ri(18)),
              ],
            ],
          ),
          SizedBox(height: context.rh(4)),

          // Online / Last seen status
          if (_presenceLabel().isNotEmpty)
            Text(
              _presenceLabel(),
              style: TextStyle(
                fontSize: context.rsp(14),
                color: conv.isOnline ? Colors.green : AppTheme.mutedSteel,
              ),
            ),
          if (_otherUser?.university != null &&
              _otherUser!.university!.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_institution?.logoUrl != null &&
                    _institution!.logoUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(context.rr(4)),
                    child: CachedNetworkImage(
                      imageUrl: _institution!.logoUrl!,
                      width: context.rw(18),
                      height: context.rh(18),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Icon(
                        LucideIcons.graduationCap,
                        size: context.ri(16),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  ),
                  SizedBox(width: context.rw(6)),
                ] else ...[
                  Icon(
                    LucideIcons.graduationCap,
                    size: context.ri(16),
                    color: AppTheme.mutedSteel,
                  ),
                  SizedBox(width: context.rw(6)),
                ],
                Flexible(
                  child: Text(
                    _otherUser!.university!,
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.mutedSteel,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreCard() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BusinessProfileScreen(
                sellerId: widget.conversation.otherUserId,
              ),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(context.rw(16)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(context.rr(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Banner thumbnail
                  if (_businessProfile!.bannerUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(context.rr(8)),
                      child: CachedNetworkImage(
                        imageUrl: _businessProfile!.bannerUrl!,
                        width: context.rw(48),
                        height: context.rh(48),
                        fit: BoxFit.cover,
                      ),
                    ),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _businessProfile!.businessName ??
                              widget.conversation.displayName,
                          style: TextStyle(
                            fontSize: context.rsp(16),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        SizedBox(height: context.rh(2)),
                        Text(
                          'Tap to view store',
                          style: TextStyle(
                            fontSize: context.rsp(13),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.store,
                    color: AppTheme.accent,
                    size: context.ri(20),
                  ),
                ],
              ),
              if (_storeStats != null) ...[
                SizedBox(height: context.rh(12)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Followers',
                      value: '${_storeStats!.followerCount}',
                    ),
                    _StatItem(
                      label: 'Products',
                      value: '${_storeStats!.totalProducts}',
                    ),
                    _StatItem(
                      label: 'Rating',
                      value: _storeStats!.averageRating.toStringAsFixed(1),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactInfo() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        context.rh(12),
        context.rw(16),
        0,
      ),
      child: Container(
        padding: EdgeInsets.all(context.rw(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(context.rr(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact',
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(8)),
            for (final phone in _businessProfile!.phoneNumbers)
              Padding(
                padding: EdgeInsets.only(bottom: context.rh(8)),
                child: Row(
                  children: [
                    Icon(
                      phone.isWhatsApp
                          ? LucideIcons.messageCircle
                          : LucideIcons.phone,
                      size: context.ri(18),
                      color: phone.isWhatsApp ? Colors.green : AppTheme.accent,
                    ),
                    SizedBox(width: context.rw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phone.number,
                            style: TextStyle(
                              fontSize: context.rsp(14),
                              fontWeight: FontWeight.w500,
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          if (phone.label.isNotEmpty)
                            Text(
                              phone.label,
                              style: TextStyle(
                                fontSize: context.rsp(12),
                                color: AppTheme.mutedSteel,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ShadIconButton.ghost(
                      icon: Icon(
                        phone.isWhatsApp
                            ? LucideIcons.externalLink
                            : LucideIcons.phone,
                        size: context.ri(18),
                      ),
                      onPressed: () =>
                          _launchPhone(phone.number, phone.isWhatsApp),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    final displayCount = _mediaMessages.length > 8 ? 8 : _mediaMessages.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        context.rh(12),
        context.rw(16),
        0,
      ),
      child: Container(
        padding: EdgeInsets.all(context.rw(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(context.rr(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Media (${_mediaMessages.length})',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedSteel,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _AllMediaScreen(mediaMessages: _mediaMessages),
                      ),
                    );
                  },
                  child: const Text('See all'),
                ),
              ],
            ),
            SizedBox(height: context.rh(8)),
            SizedBox(
              height: context.rh(80),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: displayCount,
                itemBuilder: (context, index) {
                  final msg = _mediaMessages[index];
                  final mediaUrls = _mediaMessages
                      .where((m) => m.mediaUrl != null)
                      .map((m) => m.mediaUrl!)
                      .toList();
                  final thumbnailUrls = _mediaMessages
                      .where((m) => m.mediaUrl != null)
                      .map((m) => m.thumbnailUrl)
                      .toList();
                  final mediaIndex = mediaUrls.indexOf(msg.mediaUrl!);
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == displayCount - 1 ? 0 : context.rw(8),
                    ),
                    child: SizedBox(
                      width: context.rw(80),
                      child: GestureDetector(
                        onTap: () {
                          MediaViewer.open(
                            context,
                            mediaUrls,
                            initialIndex: mediaIndex >= 0 ? mediaIndex : 0,
                            thumbnailUrls: thumbnailUrls,
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(context.rr(8)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: msg.thumbnailUrl ?? msg.mediaUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (ctx, err, trace) => Container(
                                  color: AppTheme.warmMist,
                                  child: Icon(
                                    msg.mediaType == 'video'
                                        ? LucideIcons.film
                                        : LucideIcons.image,
                                    color: AppTheme.mutedSteel,
                                  ),
                                ),
                              ),
                              if (msg.mediaType == 'video')
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(
                                        context.rr(4),
                                      ),
                                    ),
                                    child: Icon(
                                      LucideIcons.play,
                                      color: Colors.white,
                                      size: context.ri(14),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<Map<String, dynamic>> themeColors = [
    {'name': 'Purple', 'hex': '#7C3AED', 'color': Color(0xFF7C3AED)},
    {'name': 'Orange', 'hex': '#F97316', 'color': Color(0xFFF97316)},
    {'name': 'Mint', 'hex': '#10B981', 'color': Color(0xFF10B981)},
    {'name': 'Teal', 'hex': '#0D9488', 'color': Color(0xFF0D9488)},
    {'name': 'Sky Blue', 'hex': '#0EA5E9', 'color': Color(0xFF0EA5E9)},
    {'name': 'Royal Blue', 'hex': '#2563EB', 'color': Color(0xFF2563EB)},
    {'name': 'Lavender', 'hex': '#8B5CF6', 'color': Color(0xFF8B5CF6)},
    {'name': 'Rose Pink', 'hex': '#EC4899', 'color': Color(0xFFEC4899)},
    {'name': 'Crimson', 'hex': '#DC2626', 'color': Color(0xFFDC2626)},
    {'name': 'Amber Gold', 'hex': '#F59E0B', 'color': Color(0xFFF59E0B)},
    {'name': 'Forest', 'hex': '#15803D', 'color': Color(0xFF15803D)},
    {'name': 'Charcoal', 'hex': '#374151', 'color': Color(0xFF374151)},
  ];

  void _showThemeColorPicker() {
    final rootContext = context;
    final conversations = ref.read(messageProvider).conversations;
    final conv = conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
      orElse: () =>
          ref.read(messageProvider).activeConversation ?? widget.conversation,
    );
    final currentHex = conv.themeColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            context.rw(16),
            context.rh(24),
            context.rw(16),
            context.rh(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: context.rh(18)),
              Text(
                'Change Chat Theme',
                style: TextStyle(
                  fontSize: context.ri(18),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(4)),
              Text(
                'Theme changes apply to both participants in this chat.',
                style: TextStyle(
                  fontSize: context.ri(13),
                  color: AppTheme.mutedSteel,
                ),
              ),
              SizedBox(height: context.rh(24)),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemCount: themeColors.length,
                itemBuilder: (context, index) {
                  final theme = themeColors[index];
                  final isSelected =
                      (currentHex == null && theme['hex'] == '#7C3AED') ||
                      (currentHex == theme['hex']);
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await ref
                            .read(messageProvider)
                            .updateThemeColor(conv.id, theme['hex']);
                        if (rootContext.mounted) {
                          ShadToaster.of(rootContext).show(
                            ShadToast(
                              title: Text(
                                'Theme color updated to ${theme['name']}',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (rootContext.mounted) {
                          ShadToaster.of(rootContext).show(
                            ShadToast(
                              title: Text('Failed to update theme color: $e'),
                            ),
                          );
                        }
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: theme['color'] as Color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (theme['color'] as Color)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  LucideIcons.check,
                                  color: Colors.white,
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: context.rh(6)),
                        Text(
                          theme['name'] as String,
                          style: TextStyle(
                            fontSize: context.ri(11),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppTheme.charcoalInk,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions(bool isBlocked) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        context.rh(12),
        context.rw(16),
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(context.rr(16)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.all(context.rw(16)),
            child: Column(
              children: [
                // Chat Theme Color
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    LucideIcons.palette,
                    color: AppTheme.accent,
                  ),
                  title: const Text('Change theme color'),
                  onTap: _showThemeColorPicker,
                ),
                const Divider(height: 1),
                // Chat Background
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    LucideIcons.image,
                    color: AppTheme.accent,
                  ),
                  title: const Text('Chat background'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatBackgroundSettingsScreen(
                          conversationId: widget.conversation.id,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                // Archive
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    widget.conversation.isArchived
                        ? LucideIcons.archiveRestore
                        : LucideIcons.archive,
                    color: AppTheme.accent,
                  ),
                  title: Text(
                    widget.conversation.isArchived
                        ? 'Unarchive chat'
                        : 'Archive chat',
                  ),
                  onTap: _toggleArchive,
                ),
                const Divider(height: 1),
                // Block
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isBlocked ? LucideIcons.shieldCheck : LucideIcons.shieldOff,
                    color: isBlocked ? AppTheme.accent : Colors.red,
                  ),
                  title: Text(isBlocked ? 'Unblock user' : 'Block user'),
                  textColor: isBlocked ? null : Colors.red,
                  onTap: _toggleBlock,
                ),
                const Divider(height: 1),
                // Report
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.flag, color: Colors.orange),
                  title: const Text('Report user'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportScreen(
                          reportedUserId: widget.conversation.otherUserId,
                          reportedUserName: widget.conversation.displayName,
                          conversationId: widget.conversation.id,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _launchPhone(String number, bool isWhatsApp) async {
    final url = isWhatsApp
        ? Uri.parse('https://wa.me/${normalizeWhatsAppNumber(number)}')
        : Uri.parse('tel:${number.replaceAll(RegExp(r'[^\d+]'), '')}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _presenceLabel() {
    final conv = widget.conversation;
    if (conv.isOnline) return 'online';
    final lastSeen = conv.otherUserLastSeen?.toLocal();
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
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: context.rsp(18),
            fontWeight: FontWeight.w700,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(2)),
        Text(
          label,
          style: TextStyle(
            fontSize: context.rsp(12),
            color: AppTheme.mutedSteel,
          ),
        ),
      ],
    );
  }
}

class _AllMediaScreen extends StatelessWidget {
  final List<Message> mediaMessages;

  const _AllMediaScreen({required this.mediaMessages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text('Media (${mediaMessages.length})'),
      ),
      body: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          context.rw(4),
          MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
          context.rw(4),
          context.rw(4),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: context.rw(4),
          mainAxisSpacing: context.rh(4),
        ),
        itemCount: mediaMessages.length,
        itemBuilder: (context, index) {
          final msg = mediaMessages[index];
          final allUrls = mediaMessages
              .where((m) => m.mediaUrl != null)
              .map((m) => m.mediaUrl!)
              .toList();
          final allThumbnailUrls = mediaMessages
              .where((m) => m.mediaUrl != null)
              .map((m) => m.thumbnailUrl)
              .toList();
          final mediaIndex = allUrls.indexOf(msg.mediaUrl!);
          return GestureDetector(
            onTap: () {
              MediaViewer.open(
                context,
                allUrls,
                initialIndex: mediaIndex >= 0 ? mediaIndex : 0,
                thumbnailUrls: allThumbnailUrls,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.rr(6)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: msg.thumbnailUrl ?? msg.mediaUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (ctx, err, stack) => Container(
                      color: AppTheme.warmMist,
                      child: Icon(
                        msg.mediaType == 'video'
                            ? LucideIcons.film
                            : LucideIcons.image,
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  ),
                  if (msg.mediaType == 'video')
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(context.rr(4)),
                        ),
                        child: Icon(
                          LucideIcons.play,
                          color: Colors.white,
                          size: context.ri(14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
