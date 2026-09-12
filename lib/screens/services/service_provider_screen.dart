import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/service_model.dart';
import '../../providers/providers.dart';
import '../../services/follow_service.dart';
import '../../services/service_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../utils/share_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/verification_badge.dart';
import '../messages/messages_screen.dart';

/// Public storefront of a service provider — the services equivalent of the
/// seller's [BusinessProfileScreen]. Opened by tapping the provider section
/// on a service detail page; shows the provider header (avatar, bio, stats,
/// follow/message actions) with Services and Reviews tabs.
class ServiceProviderScreen extends ConsumerStatefulWidget {
  final String providerId;

  const ServiceProviderScreen({super.key, required this.providerId});

  @override
  ConsumerState<ServiceProviderScreen> createState() =>
      _ServiceProviderScreenState();
}

class _ServiceProviderScreenState extends ConsumerState<ServiceProviderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  String? _error;
  List<Service> _services = [];
  List<_ProviderReview> _reviews = [];

  String? _providerName;
  String? _providerAvatar;
  String? _providerBio;
  String? _providerEmail;
  bool _providerIsVerified = false;

  bool _isFollowing = false;
  int _followerCount = 0;
  bool _isFollowLoading = false;
  bool _isMessaging = false;

  bool get _isOwnProfile =>
      ref.read(authProvider).user?.id == widget.providerId;

  double get _averageRating {
    if (_reviews.isEmpty) return 0;
    final total = _reviews.fold<double>(0, (sum, r) => sum + r.review.rating);
    return total / _reviews.length;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final isOwner = _isOwnProfile;
      final services = await ServiceService.getServices(
        providerId: widget.providerId,
        statuses: isOwner ? ServiceStatus.values : [ServiceStatus.active],
      );

      String? name;
      String? avatar;
      String? bio;
      String? email;
      bool verified = false;
      try {
        final row = await SupabaseService.table('users')
            .select(
              'full_name, avatar_url, is_verified, '
              'service_provider_bio, service_provider_email',
            )
            .eq('id', widget.providerId)
            .maybeSingle();
        name = row?['full_name'] as String?;
        avatar = row?['avatar_url'] as String?;
        verified = row?['is_verified'] as bool? ?? false;
        bio = row?['service_provider_bio'] as String?;
        email = row?['service_provider_email'] as String?;
      } catch (_) {}

      // Provider-level reviews do not exist as a table — aggregate the
      // reviews of the provider's services (bounded so one provider with
      // many listings cannot fan out into dozens of queries).
      final aggregated = <_ProviderReview>[];
      for (final service in services.take(10)) {
        try {
          final list = await ServiceService.getServiceReviews(service.id);
          for (final review in list) {
            aggregated.add(
              _ProviderReview(serviceTitle: service.title, review: review),
            );
          }
        } catch (_) {}
      }
      aggregated.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));

      bool following = false;
      int followers = 0;
      try {
        followers = await FollowService.getFollowerCount(widget.providerId);
        final userId = ref.read(authProvider).user?.id;
        if (userId != null && userId != widget.providerId) {
          following = await FollowService.isFollowing(widget.providerId);
        }
      } catch (_) {}

      if (!mounted) return;
      final first = services.isNotEmpty ? services.first : null;
      setState(() {
        _services = services;
        _reviews = aggregated;
        _providerName = name ?? first?.providerName;
        _providerAvatar = (avatar?.isNotEmpty == true)
            ? avatar
            : first?.providerAvatar;
        _providerBio = (bio?.isNotEmpty == true) ? bio : first?.providerBio;
        _providerEmail =
            (email?.isNotEmpty == true) ? email : first?.providerPublicEmail;
        _providerIsVerified =
            verified || (first?.providerIsVerified ?? false);
        _isFollowing = following;
        _followerCount = followers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _requireAuth(VoidCallback callback) {
    if (ref.read(authProvider).isAuthenticated) {
      callback();
    } else {
      Navigator.of(context).pushNamed('/login');
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await FollowService.unfollow(widget.providerId);
        if (mounted) {
          setState(() {
            _isFollowing = false;
            if (_followerCount > 0) _followerCount--;
          });
        }
      } else {
        await FollowService.follow(widget.providerId);
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followerCount++;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Could not update follow: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _messageProvider() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    final buyerId = auth.user!.id;
    if (buyerId == widget.providerId) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('You cannot contact yourself.')),
      );
      return;
    }
    if (_isMessaging) return;
    setState(() => _isMessaging = true);
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      ),
    );
    try {
      await ref
          .read(messageProvider)
          .createAndOpenConversation(
            buyerId: buyerId,
            sellerId: widget.providerId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      final activeConv = ref.read(messageProvider).activeConversation;
      if (activeConv != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConversationScreen(conversation: activeConv),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ShadToaster.of(context).show(
          ShadToast(title: Text('Failed to start chat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isMessaging = false);
    }
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch email: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 6),
        ),
      );
    }

    if (_error != null && _services.isEmpty && _providerName == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Provider'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: context.ri(48),
                color: AppTheme.mutedSteel,
              ),
              SizedBox(height: context.rh(16)),
              const Text('Could not load provider'),
              const SizedBox(height: 16),
              ShadButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final displayName = _providerName ?? 'Service Provider';

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildBanner(displayName),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(displayName),
                    const SizedBox(height: 16),
                    _buildStatsRow(),
                    if (!_isOwnProfile) ...[
                      const SizedBox(height: 16),
                      _buildActionRow(),
                    ],
                    if (_providerBio?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      _buildBio(),
                    ],
                    if (_providerEmail?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      _buildEmailRow(),
                    ],
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProviderTabBarDelegate(
                tabController: _tabController,
                serviceCount: _services.length,
                reviewCount: _reviews.length,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [_buildServicesTab(), _buildReviewsTab()],
          ),
        ),
      ),
    );
  }

  // ── Banner ──────────────────────────────────────────────────────────

  Widget _buildBanner(String displayName) {
    return SliverAppBar(
      expandedHeight: context.rh(180),
      pinned: true,
      backgroundColor: AppTheme.headerBarSolid,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.accent, AppTheme.accentBright],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(
              LucideIcons.briefcaseBusiness,
              size: context.ri(64),
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
      leading: Container(
        margin: context.rAll(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: ShadIconButton.ghost(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: ShadIconButton.ghost(
            icon: Icon(
              LucideIcons.share2,
              color: Colors.white,
              size: context.ri(18),
            ),
            onPressed: () {
              ShareHelper.shareText(
                'Check out "$displayName" services on Instiy\n\n'
                'Link: https://instiy.com/provider/${widget.providerId}',
                context: context,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Profile header ──────────────────────────────────────────────────

  Widget _buildProfileHeader(String displayName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ShadAvatar(
              (_providerAvatar?.isNotEmpty == true) ? _providerAvatar : null,
              size: Size(context.ri(64), context.ri(64)),
              backgroundColor: AppTheme.accent,
              placeholder: Text(
                displayName[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: context.rsp(22),
                ),
              ),
            ),
            if (_providerIsVerified)
              Positioned(
                bottom: -2,
                right: -2,
                child: VerificationBadge(size: context.ri(18)),
              ),
          ],
        ),
        SizedBox(width: context.rw(14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: TextStyle(
                  fontSize: context.rsp(18),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(2)),
              Text(
                'Service Provider',
                style: TextStyle(
                  fontSize: context.rsp(13),
                  color: AppTheme.mutedSteel,
                ),
              ),
              SizedBox(height: context.rh(4)),
              Text(
                '$_followerCount follower${_followerCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(14)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Services',
            value: '${_services.length}',
            icon: LucideIcons.briefcaseBusiness,
          ),
          _StatItem(
            label: 'Rating',
            value: _reviews.isEmpty
                ? '—'
                : _averageRating.toStringAsFixed(1),
            icon: LucideIcons.star,
          ),
          _StatItem(
            label: 'Reviews',
            value: '${_reviews.length}',
            icon: LucideIcons.messageSquare,
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: _isFollowing
              ? AppButton.outline(
                  onPressed: () => _requireAuth(_toggleFollow),
                  leading: Icon(
                    LucideIcons.userMinus,
                    size: context.ri(18),
                  ),
                  child: Text(
                    _isFollowLoading ? 'Please wait…' : 'Unfollow',
                  ),
                )
              : AppButton(
                  onPressed: () => _requireAuth(_toggleFollow),
                  leading: Icon(
                    LucideIcons.userPlus,
                    size: context.ri(18),
                    color: Colors.white,
                  ),
                  child: Text(
                    _isFollowLoading ? 'Please wait…' : 'Follow',
                  ),
                ),
        ),
        SizedBox(width: context.rw(12)),
        Expanded(
          child: AppButton.outline(
            onPressed: _messageProvider,
            leading: Icon(
              LucideIcons.messageSquare,
              size: context.ri(18),
            ),
            child: Text(_isMessaging ? 'Opening…' : 'Message'),
          ),
        ),
      ],
    );
  }

  Widget _buildBio() {
    return Container(
      width: double.infinity,
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.fileText,
                size: context.ri(16),
                color: AppTheme.accent,
              ),
              SizedBox(width: context.rw(6)),
              Text(
                'About',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(8)),
          Text(
            _providerBio!,
            style: TextStyle(
              color: AppTheme.charcoalInk,
              height: 1.5,
              fontSize: context.rsp(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchEmail(_providerEmail!),
        borderRadius: BorderRadius.circular(context.rr(12)),
        child: Container(
          width: double.infinity,
          padding: context.rAll(14),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(12)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.mail,
                size: context.ri(16),
                color: AppTheme.accent,
              ),
              SizedBox(width: context.rw(10)),
              Expanded(
                child: Text(
                  _providerEmail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Services tab ────────────────────────────────────────────────────

  Widget _buildServicesTab() {
    if (_services.isEmpty) {
      return ListView(
        padding: context.rAll(24),
        children: [
          SizedBox(height: context.rh(48)),
          Icon(
            LucideIcons.briefcaseBusiness,
            size: context.ri(56),
            color: AppTheme.mutedSteel.withValues(alpha: 0.4),
          ),
          SizedBox(height: context.rh(12)),
          Center(
            child: Text(
              'No services yet',
              style: TextStyle(
                fontSize: context.rsp(15),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ),
        ],
      );
    }
    return GridView.builder(
      padding: context.rAll(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: context.rh(12),
        crossAxisSpacing: context.rw(12),
        mainAxisExtent: context.rh(250),
      ),
      itemCount: _services.length,
      itemBuilder: (context, index) =>
          _ProviderServiceCard(service: _services[index]),
    );
  }

  // ── Reviews tab ─────────────────────────────────────────────────────

  Widget _buildReviewsTab() {
    if (_reviews.isEmpty) {
      return ListView(
        padding: context.rAll(24),
        children: [
          SizedBox(height: context.rh(48)),
          Icon(
            LucideIcons.messageSquare,
            size: context.ri(56),
            color: AppTheme.mutedSteel.withValues(alpha: 0.4),
          ),
          SizedBox(height: context.rh(12)),
          Center(
            child: Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: context.rsp(15),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: context.rAll(16),
      itemCount: _reviews.length,
      separatorBuilder: (_, _) => SizedBox(height: context.rh(12)),
      itemBuilder: (context, index) {
        final entry = _reviews[index];
        final review = entry.review;
        return Container(
          padding: context.rAll(14),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(14)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShadAvatar(
                    (review.reviewerAvatar?.isNotEmpty == true)
                        ? review.reviewerAvatar
                        : null,
                    size: Size(context.ri(36), context.ri(36)),
                    backgroundColor: AppTheme.accent,
                    placeholder: Text(
                      (review.reviewerName ?? 'R')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: context.rw(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.reviewerName ?? 'Customer',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: context.rsp(13),
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        Text(
                          DateFormat(
                            'MMM d, yyyy',
                          ).format(review.createdAt),
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.star,
                        size: context.ri(14),
                        color: AppTheme.warningAmber,
                      ),
                      SizedBox(width: context.rw(4)),
                      Text(
                        '${review.rating}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: context.rsp(13),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (review.comment?.isNotEmpty == true) ...[
                SizedBox(height: context.rh(8)),
                Text(
                  review.comment!,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.charcoalInk,
                    height: 1.45,
                  ),
                ),
              ],
              SizedBox(height: context.rh(8)),
              Text(
                'On: ${entry.serviceTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.rsp(11),
                  color: AppTheme.mutedSteel,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProviderReview {
  final String serviceTitle;
  final ServiceReview review;

  const _ProviderReview({required this.serviceTitle, required this.review});
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: context.ri(18), color: AppTheme.accent),
        SizedBox(height: context.rh(4)),
        Text(
          value,
          style: TextStyle(
            fontSize: context.rsp(16),
            fontWeight: FontWeight.w700,
            color: AppTheme.charcoalInk,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: context.rsp(11),
            color: AppTheme.mutedSteel,
          ),
        ),
      ],
    );
  }
}

class _ProviderServiceCard extends StatelessWidget {
  final Service service;

  const _ProviderServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final imageUrl = service.imageUrls.isNotEmpty
        ? service.imageUrls.first
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).pushNamed('/service-detail', arguments: service.id),
        borderRadius: BorderRadius.circular(context.rr(14)),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(14)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.rr(14)),
                ),
                child: SizedBox(
                  height: context.rh(130),
                  width: double.infinity,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: AppTheme.warmMist,
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: AppTheme.warmMist,
                            child: Icon(
                              LucideIcons.image,
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        )
                      : Container(
                          color: AppTheme.warmMist,
                          child: Icon(
                            LucideIcons.image,
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: context.rAll(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.rsp(13),
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(height: context.rh(4)),
                    Text(
                      'From ${formatGhs(service.startingPrice)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: context.rsp(13),
                        color: AppTheme.accent,
                      ),
                    ),
                    SizedBox(height: context.rh(4)),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.star,
                          size: context.ri(12),
                          color: AppTheme.warningAmber,
                        ),
                        SizedBox(width: context.rw(4)),
                        Text(
                          service.averageRating != null
                              ? service.averageRating!.toStringAsFixed(1)
                              : 'New',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                        if (service.reviewCount != null &&
                            service.reviewCount! > 0)
                          Text(
                            ' (${service.reviewCount})',
                            style: TextStyle(
                              fontSize: context.rsp(11),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                      ],
                    ),
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

class _ProviderTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final int serviceCount;
  final int reviewCount;

  const _ProviderTabBarDelegate({
    required this.tabController,
    required this.serviceCount,
    required this.reviewCount,
  });

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppTheme.cleanBackground,
      child: TabBar(
        controller: tabController,
        indicatorColor: AppTheme.accent,
        labelColor: AppTheme.accent,
        unselectedLabelColor: AppTheme.mutedSteel,
        tabs: [
          Tab(text: 'Services ($serviceCount)'),
          Tab(text: 'Reviews ($reviewCount)'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProviderTabBarDelegate oldDelegate) {
    return oldDelegate.serviceCount != serviceCount ||
        oldDelegate.reviewCount != reviewCount;
  }
}
