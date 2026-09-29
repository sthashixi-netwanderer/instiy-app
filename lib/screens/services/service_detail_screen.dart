import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_player/video_player.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../models/institution_model.dart';
import '../../models/service_model.dart';
import '../../services/institution_service.dart';
import '../../services/service_service.dart';
import '../../providers/providers.dart';
import '../../widgets/service_review_section.dart';
import '../../widgets/media_viewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../messages/messages_screen.dart';
import 'service_report_screen.dart';

/// Public service detail: gallery, description, tiered packages and the
/// provider card. The owner additionally gets edit + status controls —
/// service management is reachable only from the Services screen.
class ServiceDetailScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  ConsumerState<ServiceDetailScreen> createState() =>
      _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  Service? _service;
  bool _isLoading = true;
  String? _error;
  int? _viewCount;

  /// Records the visit once per screen lifetime — silent reloads after
  /// edits or review changes must not re-run the (deduped) view RPC.
  bool _recordedView = false;

  /// Index into the sorted packages list driving the plan tabs — the
  /// active tab is the plan quoted when contacting the provider.
  int _activePlanIndex = 0;

  /// Keys for the plan tabs so a panel swipe can scroll the newly
  /// active tab back into view when tabs overflow the screen.
  final Map<int, GlobalKey> _planTabKeys = {};

  /// Institutions for the availability card's logos — loaded once; the
  /// card keeps its fallback icon until (and unless) they arrive.
  List<Institution> _institutions = [];
  int _galleryPage = 0;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadService();
    unawaited(_loadInstitutions());
  }

  /// Fetches the institution list so the availability card can show
  /// each listed institution's logo.
  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutions();
      if (!mounted) return;
      setState(() => _institutions = institutions);
    } catch (_) {
      // Logos are decorative — the card keeps its fallback icon.
    }
  }

  Future<void> _loadService({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final service = await ServiceService.getService(widget.serviceId);
      if (!mounted) return;
      _planTabKeys.removeWhere(
        (key, _) => key >= (service?.sortedPackages.length ?? 0),
      );
      setState(() {
        _service = service;
        _isLoading = false;
      });
      if (service != null && !_recordedView) {
        _recordedView = true;
        unawaited(_recordView());
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Counts this visit (deduped server-side per user / per anonymous IP).
  Future<void> _recordView() async {
    final count = await ServiceService.recordServiceView(_service!.id);
    if (mounted && count > 0) {
      setState(() => _viewCount = count);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _isOwnService {
    final userId = ref.read(authProvider).user?.id;
    return _service != null && userId == _service!.providerId;
  }

  void _openEditor() {
    final service = _service;
    if (service == null) return;
    Navigator.of(
      context,
    ).pushNamed('/create-service', arguments: service).then((_) {
      // Silent: edits now save in the background, so returning from the
      // wizard must not flash a loader — fresh data arrives via the
      // provider notification when the save lands.
      if (mounted) _loadService(silent: true);
    });
  }

  void _reportService() {
    final service = _service;
    if (service == null) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceReportScreen(
          serviceId: service.id,
          serviceTitle: service.title,
          providerId: service.providerId,
        ),
      ),
    );
  }

  Future<void> _toggleStatus() async {
    final service = _service;
    if (service == null) return;
    final newStatus = service.isActive
        ? ServiceStatus.paused
        : ServiceStatus.active;
    if (newStatus == ServiceStatus.active) {
      final isProvider = await ServiceService.isServiceProvider();
      if (!isProvider) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast.destructive(
              title: Text('Provider access required'),
              description: Text(
                'Your service provider status is disabled. You cannot publish services.',
              ),
            ),
          );
        }
        return;
      }
    }
    try {
      await ServiceService.setServiceStatus(service.id, newStatus);
      await _loadService();
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: Text(
              newStatus == ServiceStatus.active
                  ? 'Service published'
                  : 'Service paused',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Couldn\'t update the service: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the session so ownership gates re-evaluate if auth changes
    // while this screen is open — a stale read must never leak the
    // contact button to the listing owner.
    ref.watch(authProvider);
    ref.listen(serviceProvider, (previous, next) {
      if (mounted) _loadService(silent: true);
    });

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text(
          _service?.title ?? 'Service',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_service != null && !_isOwnService)
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.flag, size: 20),
              onPressed: _reportService,
            ),
          if (_isOwnService)
            ShadIconButton.ghost(
              icon: Icon(
                _service!.isActive ? LucideIcons.pause : LucideIcons.play,
                size: 20,
              ),
              onPressed: _toggleStatus,
            ),
          if (_isOwnService)
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.pencil, size: 20),
              onPressed: _openEditor,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _service == null
                  ? _buildNotFoundError()
                  : _buildContent(context, _service!),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.cloudOff,
            size: context.ri(48),
            color: Colors.grey[300],
          ),
          SizedBox(height: context.rh(12)),
          Text(
            'Couldn\'t load this service',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: context.rsp(15),
            ),
          ),
          SizedBox(height: context.rh(12)),
          ShadButton.outline(
            onPressed: _loadService,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundError() {
    return Center(
      child: Text(
        'This service is no longer available.',
        style: TextStyle(
          color: AppTheme.mutedSteel,
          fontSize: context.rsp(14),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Service service) {
    final packages = service.sortedPackages;
    final activeIndex = packages.isEmpty
        ? 0
        : _activePlanIndex.clamp(0, packages.length - 1);
    return ListView(
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
        context.rw(16),
        context.rh(24),
      ),
      children: [
        _buildGallery(service),
        SizedBox(height: context.rh(16)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                service.title,
                style: TextStyle(
                  fontSize: context.rsp(21),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        if (_viewCount != null) ...[
          SizedBox(height: context.rh(6)),
          Row(
            children: [
              Icon(
                LucideIcons.eye,
                size: context.ri(14),
                color: AppTheme.mutedSteel,
              ),
              SizedBox(width: context.rw(4)),
              Text(
                '$_viewCount ${_viewCount == 1 ? 'view' : 'views'}',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: context.rh(8)),
        _buildMetaRow(service),
        SizedBox(height: context.rh(16)),
        if (_isOwnService) ...[
          _buildOwnerBanner(service),
          SizedBox(height: context.rh(16)),
        ],
        _buildSectionTitle('About this service'),
        SizedBox(height: context.rh(8)),
        Text(
          service.description ?? 'No description provided.',
          style: TextStyle(
            color: AppTheme.mutedSteel,
            height: 1.6,
            fontSize: context.rsp(14),
          ),
        ),
        if (service.searchTags.isNotEmpty) ...[
          SizedBox(height: context.rh(16)),
          Wrap(
            spacing: context.rw(8),
            runSpacing: context.rh(8),
            children: [
              for (final tag in service.searchTags.take(8))
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(10),
                    vertical: context.rh(5),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(12)),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: context.rsp(11),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
            ],
          ),
        ],
        SizedBox(height: context.rh(16)),
        _buildAvailability(context, service),
        if (packages.isNotEmpty) ...[
          SizedBox(height: context.rh(24)),
          _buildSectionTitle('Plans & Packages'),
          SizedBox(height: context.rh(12)),
          _buildPlanTabs(packages, activeIndex),
          SizedBox(height: context.rh(12)),
          _PlanSwipeDeck(
            packages: packages,
            activeIndex: activeIndex,
            onPlanChanged: (index) => _goToPlan(index, revealTab: true),
          ),
        ],
        SizedBox(height: context.rh(24)),
        if (service.providerName != null) _buildProviderCard(service),
        SizedBox(height: context.rh(24)),
        if (!_isOwnService)
          ShadButton(
            onPressed: () => _contactProvider(context, ref, service),
            child: const Text(
              'Contact Provider',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        SizedBox(height: context.rh(32)),
        ServiceReviewSection(
          serviceId: service.id,
          providerId: service.providerId,
          onReviewsChanged: _loadService,
        ),
      ],
    );
  }

  Widget _buildAvailability(BuildContext context, Service service) {
    return Container(
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.warmMist,
        borderRadius: BorderRadius.circular(context.rr(12)),
      ),
      child: Row(
        children: [
          if (service.institutionCodes.isNotEmpty)
            _buildInstitutionLogos(service.institutionCodes)
          else
            Icon(
              LucideIcons.building,
              size: context.ri(18),
              color: AppTheme.mutedSteel,
            ),
          SizedBox(width: context.rw(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.institutionCodes.isEmpty
                      ? 'Available at all institutions'
                      : 'Available at ${service.institutionCodes.length} '
                        'institution'
                        '${service.institutionCodes.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                if (service.institutionCodes.isNotEmpty)
                  Text(
                    service.institutionCodes.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Overlapping circular logos for the listed institutions — up to
  /// three with a "+N" badge past that, and a graduation-cap stand-in
  /// for any institution without a logo.
  Widget _buildInstitutionLogos(List<String> codes) {
    const double logoSize = 32;
    const double step = 12;
    final shown = codes.take(3).toList();
    final extra = codes.length - shown.length;
    return SizedBox(
      width: logoSize + step * (shown.length - 1) + (extra > 0 ? step : 0),
      height: logoSize,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: i * step, child: _institutionLogo(shown[i])),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: _logoCircle(
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One circular slot — the institution's logo when it has one,
  /// otherwise a graduation-cap placeholder.
  Widget _institutionLogo(String code) {
    final logoUrl = _institutionFor(code)?.logoUrl;
    return _logoCircle(
      child: ClipOval(
        child: SizedBox(
          width: 28,
          height: 28,
          child: logoUrl != null && logoUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: logoUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 56,
                  placeholder: (_, _) => Container(color: AppTheme.warmMist),
                  errorWidget: (_, _, _) => _logoFallback(),
                )
              : _logoFallback(),
        ),
      ),
    );
  }

  Widget _logoFallback() {
    return Container(
      color: AppTheme.warmMist,
      alignment: Alignment.center,
      child: const Icon(
        LucideIcons.graduationCap,
        size: 14,
        color: AppTheme.mutedSteel,
      ),
    );
  }

  /// Circular badge with a surface ring so overlapping logos stay
  /// readable on the mist background.
  Widget _logoCircle({required Widget child}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.pureSurface,
        border: Border.all(color: AppTheme.pureSurface, width: 2),
      ),
      child: child,
    );
  }

  /// Resolves an institution by its availability code (name accepted as
  /// a fallback, matching the product detail behaviour).
  Institution? _institutionFor(String code) {
    final needle = code.toLowerCase();
    for (final institution in _institutions) {
      if (institution.code.toLowerCase() == needle ||
          institution.name.toLowerCase() == needle) {
        return institution;
      }
    }
    return null;
  }

  Widget _buildGallery(Service service) {
    final videos = service.videoUrls;
    final images = service.imageUrls;
    final media = [...videos, ...images];
    if (media.isEmpty) {
      return Container(
        height: context.rh(200),
        decoration: BoxDecoration(
          color: AppTheme.warmMist,
          borderRadius: BorderRadius.circular(context.rr(16)),
        ),
        child: Center(
          child: Icon(
            LucideIcons.image,
            size: context.ri(40),
            color: AppTheme.mutedSteel,
          ),
        ),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.rr(16)),
          child: SizedBox(
            height: context.rh(220),
            child: PageView.builder(
              itemCount: media.length,
              onPageChanged: (i) => setState(() => _galleryPage = i),
              itemBuilder: (context, index) {
                if (index < videos.length) {
                  return _ServiceVideoTile(
                    videoUrl: videos[index],
                    onTap: () => MediaViewer.open(
                      context,
                      media,
                      initialIndex: index,
                    ),
                  );
                }
                final imageIndex = index - videos.length;
                return GestureDetector(
                  onTap: () => MediaViewer.open(
                    context,
                    media,
                    initialIndex: index,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: images[imageIndex],
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    placeholder: (_, _) =>
                        Container(color: AppTheme.warmMist),
                    errorWidget: (_, _, _) =>
                        Container(color: AppTheme.warmMist),
                  ),
                );
              },
            ),
          ),
        ),
        if (media.length > 1) ...[
          SizedBox(height: context.rh(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < media.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: context.rw(3)),
                  width: _galleryPage == i ? context.rw(16) : context.rw(6),
                  height: context.rh(6),
                  decoration: BoxDecoration(
                    color: _galleryPage == i
                        ? AppTheme.accent
                        : AppTheme.whisperBorder,
                    borderRadius: BorderRadius.circular(context.rr(4)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMetaRow(Service service) {
    final delivery = service.minDeliveryTimeFormatted ??
        (service.minDeliveryDays != null
            ? '${service.minDeliveryDays} day${service.minDeliveryDays == 1 ? '' : 's'}'
            : null);
    return Wrap(
      spacing: context.rw(14),
      runSpacing: context.rh(6),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (service.reviewCount != null && service.reviewCount! > 0) ...[
          Icon(Icons.star, size: context.ri(16), color: Colors.amber),
          Text(
            '${service.averageRating?.toStringAsFixed(1) ?? '0.0'} '
            '(${service.reviewCount} reviews)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: context.rsp(13),
            ),
          ),
        ],
        if (service.categoryName != null) ...[
          Icon(
            LucideIcons.tag,
            size: context.ri(14),
            color: AppTheme.mutedSteel,
          ),
          Text(
            service.categoryName!,
            style: TextStyle(
              color: AppTheme.mutedSteel,
              fontSize: context.rsp(13),
            ),
          ),
        ],
        if (delivery != null) ...[
          Icon(
            LucideIcons.clock,
            size: context.ri(14),
            color: AppTheme.mutedSteel,
          ),
          Text(
            delivery,
            style: TextStyle(
              color: AppTheme.mutedSteel,
              fontSize: context.rsp(13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOwnerBanner(Service service) {
    return Container(
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.rr(12)),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            service.isActive ? LucideIcons.eye : LucideIcons.eyeOff,
            size: context.ri(18),
            color: AppTheme.accent,
          ),
          SizedBox(width: context.rw(10)),
          Expanded(
            child: Text(
              service.isActive
                  ? 'Your listing is live. Customers can find it in Discover.'
                  : 'This listing is ${service.status.displayName.toLowerCase()} — hidden from Discover.',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.charcoalInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: context.rsp(16),
        color: AppTheme.charcoalInk,
      ),
    );
  }

  /// Plan tabs built from the package names, centered on screen —
  /// tapping a tab or swiping the panel switches the detail below it.
  /// The active tab is always the plan quoted when contacting the
  /// provider. Tabs scroll horizontally if too many to fit at once.
  Widget _buildPlanTabs(List<ServicePackage> packages, int activeIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < packages.length; i++) ...[
                  _PlanTab(
                    key: _planTabKeys.putIfAbsent(i, () => GlobalKey()),
                    label: packages[i].name.isNotEmpty
                        ? packages[i].name
                        : packages[i].tier.displayName,
                    selected: i == activeIndex,
                    onTap: () => _goToPlan(i),
                    isPopular: packages[i].isPopular,
                    tier: packages[i].tier,
                  ),
                  if (i < packages.length - 1)
                    SizedBox(width: context.rw(8)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Switches the active plan tab, optionally scrolling the tab row so
  /// the newly active tab is visible after a panel swipe.
  void _goToPlan(int index, {bool revealTab = false}) {
    setState(() => _activePlanIndex = index);
    if (!revealTab) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _planTabKeys[index]?.currentContext;
      if (tabContext != null) {
        Scrollable.ensureVisible(
          tabContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildProviderCard(Service service) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Tapping the provider section opens their public storefront.
        onTap: () => Navigator.of(context).pushNamed(
          '/service-provider',
          arguments: service.providerId,
        ),
        borderRadius: BorderRadius.circular(context.rr(12)),
        child: Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.warmMist,
            borderRadius: BorderRadius.circular(context.rr(12)),
          ),
          child: Row(
            children: [
              ShadAvatar(
                (service.providerAvatar != null &&
                        service.providerAvatar!.isNotEmpty)
                    ? service.providerAvatar
                    : null,
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (service.providerName ?? 'S')[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: context.rsp(14),
                  ),
                ),
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.providerName ?? 'Service Provider',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.rsp(14),
                      ),
                    ),
                Text(
                  'Service Provider',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
                if (service.providerBio != null &&
                    service.providerBio!.isNotEmpty) ...[
                  SizedBox(height: context.rh(4)),
                  Text(
                    service.providerBio!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                      height: 1.4,
                    ),
                  ),
                ],
                // The public contact email is a customer affordance — the
                // listing owner has no one to contact on their own page.
                if (!_isOwnService &&
                    service.providerPublicEmail != null &&
                    service.providerPublicEmail!.isNotEmpty) ...[
                  SizedBox(height: context.rh(6)),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _launchEmail(
                        service.providerPublicEmail!,
                        serviceTitle: service.title,
                      ),
                      borderRadius: BorderRadius.circular(context.rr(4)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: context.rh(3)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.mail,
                              size: context.ri(13),
                              color: AppTheme.accent,
                            ),
                            SizedBox(width: context.rw(6)),
                            Flexible(
                              child: Text(
                                service.providerPublicEmail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: context.rsp(12),
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    foregroundColor: AppTheme.accent,
                    onPressed: () => _showProviderBioSheet(service),
                    child: Text(
                      (service.providerBio != null &&
                              service.providerBio!.isNotEmpty)
                          ? 'Read full bio'
                          : 'About provider',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
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

  Future<void> _launchEmail(String email, {String? serviceTitle}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;

    String? query;
    if (serviceTitle != null && serviceTitle.trim().isNotEmpty) {
      query = 'subject=${Uri.encodeComponent('Inquiry regarding ${serviceTitle.trim()}')}';
    }

    final emailLaunchUri = Uri(
      scheme: 'mailto',
      path: trimmed,
      query: query,
    );

    try {
      bool launched = false;
      try {
        launched = await launchUrl(
          emailLaunchUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(emailLaunchUri);
        } catch (_) {}
      }

      if (!launched && query != null) {
        final simpleUri = Uri(scheme: 'mailto', path: trimmed);
        try {
          launched = await launchUrl(
            simpleUri,
            mode: LaunchMode.externalApplication,
          );
          if (!launched) {
            launched = await launchUrl(simpleUri);
          }
        } catch (_) {}
      }

      if (!launched && mounted) {
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            title: Text('Could not open email app'),
            description:
                Text('Please check if an email app is configured on your device.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Could not launch email app: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            title: Text('Could not open email app'),
            description:
                Text('Please check if an email app is configured on your device.'),
          ),
        );
      }
    }
  }

  /// Full provider bio in a full-height modal sheet — opens covering the
  /// screen, drags down to dismiss and snaps between heights.
  void _showProviderBioSheet(Service service) {
    final bio = service.providerBio;
    final hasBio = bio != null && bio.trim().isNotEmpty;
    final email = service.providerPublicEmail;
    final hasEmail = email != null && email.trim().isNotEmpty;
    showShadSheet(
      context: context,
      builder: (ctx) => ShadSheet(
        expandable: true,
        initialSize: 1,
        minSize: 0.4,
        maxSize: 1,
        snap: true,
        snapSizes: const [0.7, 0.95],
        backgroundColor: AppTheme.pureSurface,
        title: Text(
          'About ${service.providerName ?? 'the provider'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShadAvatar(
                  (service.providerAvatar != null &&
                          service.providerAvatar!.isNotEmpty)
                      ? service.providerAvatar
                      : null,
                  backgroundColor: AppTheme.accent,
                  placeholder: Text(
                    (service.providerName ?? 'S')[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: ctx.rsp(14),
                    ),
                  ),
                ),
                SizedBox(width: ctx.rw(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.providerName ?? 'Service Provider',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: ctx.rsp(15),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                      Text(
                        'Service Provider',
                        style: TextStyle(
                          fontSize: ctx.rsp(12),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: ctx.rh(16)),
            Text(
              hasBio
                  ? bio
                  : 'No bio available for this provider yet.',
              style: TextStyle(
                fontSize: ctx.rsp(14),
                color: hasBio ? AppTheme.charcoalInk : AppTheme.mutedSteel,
                height: 1.6,
              ),
            ),
            // Customers only — hidden for the listing owner like the card.
            if (hasEmail && !_isOwnService) ...[
              SizedBox(height: ctx.rh(16)),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _launchEmail(
                    email,
                    serviceTitle: service.title,
                  ),
                  borderRadius: BorderRadius.circular(ctx.rr(4)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: ctx.rh(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.mail,
                          size: ctx.ri(14),
                          color: AppTheme.accent,
                        ),
                        SizedBox(width: ctx.rw(6)),
                        Flexible(
                          child: Text(
                            email,
                            style: TextStyle(
                              fontSize: ctx.rsp(13),
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                              decorationColor: AppTheme.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _contactProvider(
    BuildContext context,
    WidgetRef ref,
    Service service,
  ) async {
    final authProv = ref.read(authProvider);
    if (!authProv.isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }

    final buyerId = authProv.user!.id;
    final providerId = service.providerId;

    if (buyerId == providerId) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('You cannot contact yourself.')),
      );
      return;
    }

    // The active plan tab is quoted so the chat references the exact
    // plan the customer is viewing. Services without any packages fall
    // back to the service-level starting price.
    final packages = service.sortedPackages;
    ServicePackage? selectedPackage;
    if (packages.isNotEmpty) {
      selectedPackage =
          packages[_activePlanIndex.clamp(0, packages.length - 1)];
    }

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final msgProv = ref.read(messageProvider);

      final serviceRef = {
        'product_id': service.id,
        'title': service.title,
        'price': selectedPackage?.price ?? service.startingPrice,
        'image_url': service.imageUrls.isNotEmpty
            ? service.imageUrls.first
            : null,
        // Marks this reference as a service so the chat's card routes to
        // the service detail screen instead of the product one.
        'type': 'service',
        // Quoted plan — the chat card shows the package name + its price.
        if (selectedPackage != null)
          'package_name': selectedPackage.name.isNotEmpty
              ? selectedPackage.name
              : selectedPackage.tier.displayName,
      };

      await msgProv.createAndOpenConversation(
        buyerId: buyerId,
        sellerId: providerId,
        productReference: serviceRef,
      );

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading indicator
        final activeConv = msgProv.activeConversation;
        if (activeConv != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(conversation: activeConv),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading indicator
        ShadToaster.of(context).show(
          ShadToast(title: Text('Failed to start chat: $e')),
        );
      }
    }
  }
}

/// A plan tab showing the package (or tier) name. Tapping it switches the
/// detail panel below — the active tab is the plan quoted on contact.
/// Popular packages get a star and standard-tier packages a STANDARD chip
/// so the marking is visible right on the tab.
class _PlanTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isPopular;
  final ServiceTier tier;

  const _PlanTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isPopular,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(16),
          vertical: context.rh(10),
        ),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(20)),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPopular)
              Padding(
                padding: EdgeInsets.only(right: context.rw(5)),
                child: Icon(
                  LucideIcons.star,
                  size: context.ri(14),
                  color: selected
                      ? Colors.amber.shade200
                      : Colors.amber.shade700,
                ),
              ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.rsp(13),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.mutedSteel,
              ),
            ),
            if (!isPopular && tier == ServiceTier.standard)
              Container(
                margin: EdgeInsets.only(left: context.rw(6)),
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(6),
                  vertical: context.rh(2),
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.rr(6)),
                ),
                child: Text(
                  'STANDARD',
                  style: TextStyle(
                    fontSize: context.rsp(9),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: selected ? Colors.white : AppTheme.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Swipeable plan deck: the active panel follows the finger while
/// dragging, with the neighbouring plan sliding in alongside it. On
/// release a fling always advances, a slow drag commits only past
/// halfway, and anything less springs back. Tab taps ride the same
/// slide, so the tabs, the panel and the contact quote always agree on
/// the active plan.
class _PlanSwipeDeck extends StatefulWidget {
  final List<ServicePackage> packages;
  final int activeIndex;
  final ValueChanged<int> onPlanChanged;

  const _PlanSwipeDeck({
    required this.packages,
    required this.activeIndex,
    required this.onPlanChanged,
  });

  @override
  State<_PlanSwipeDeck> createState() => _PlanSwipeDeckState();
}

class _PlanSwipeDeckState extends State<_PlanSwipeDeck>
    with SingleTickerProviderStateMixin {
  /// Continuous plan position: whole numbers are settled plans,
  /// fractions are mid-swipe. Dragging writes it directly so the panels
  /// track the finger; [_settleTo] animates it to a whole number on
  /// release and after tab taps.
  double _page = 0;
  double _animFrom = 0;
  double _animTo = 0;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  /// Release velocity (px/s) above which a swipe always advances.
  static const double _flingVelocity = 350;

  @override
  void initState() {
    super.initState();
    _page = widget.activeIndex.clamp(0, widget.packages.length - 1).toDouble();
    _settle.addListener(() {
      setState(() {
        if (_settle.isCompleted) {
          _page = _animTo;
        } else {
          final t = Curves.easeOutCubic.transform(_settle.value);
          _page = _animFrom + (_animTo - _animFrom) * t;
        }
      });
    });
  }

  @override
  void didUpdateWidget(_PlanSwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.packages.length != oldWidget.packages.length) {
      // The plan list changed underneath us — land on the active plan.
      _settle.stop();
      _page = widget.activeIndex
          .clamp(0, widget.packages.length - 1)
          .toDouble();
    } else if (widget.activeIndex != oldWidget.activeIndex &&
        _page != widget.activeIndex.toDouble()) {
      // Tab tap (or an external change): slide to the newly active plan.
      _settleTo(widget.activeIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// Animates [_page] to [target]. The duration scales with distance so
  /// short spring-backs stay snappy while full plan changes keep the
  /// familiar ~300ms slide.
  void _settleTo(double target) {
    final distance = (target - _page).abs().clamp(0.0, 1.0);
    _settle.duration = Duration(milliseconds: (180 + 220 * distance).round());
    _animFrom = _page;
    _animTo = target;
    _settle.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    _settle.stop();
    final raw = _page - (details.primaryDelta ?? 0) / width;
    final max = widget.packages.length - 1;
    setState(() {
      // Past the first/last plan the panel keeps moving with a third of
      // the finger travel instead of stopping dead (iOS-style resistance).
      if (raw < 0) {
        _page = raw / 3;
      } else if (raw > max) {
        _page = max + (raw - max) / 3;
      } else {
        _page = raw;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    var target = _page.round();
    if (velocity <= -_flingVelocity) {
      target = _page.floor() + 1; // flung left — next plan
    } else if (velocity >= _flingVelocity) {
      target = _page.ceil() - 1; // flung right — previous plan
    }
    target = target.clamp(0, widget.packages.length - 1);
    if (target == widget.activeIndex) {
      _settleTo(target.toDouble());
    } else {
      // The parent updates the active plan and reports back through
      // didUpdateWidget, which rides the same slide to the new plan.
      widget.onPlanChanged(target);
    }
  }

  /// The gesture arena handed the drag to the vertical page scroll —
  /// return to the nearest settled plan.
  void _onDragCancel() {
    _settleTo(
      _page.roundToDouble().clamp(0.0, (widget.packages.length - 1).toDouble()),
    );
  }

  /// Stable identity for a plan's panel so its element survives
  /// reorders and reloads of the packages list.
  Object _planKey(int i) =>
      widget.packages[i].id ??
      '${widget.packages[i].tier.name}:${widget.packages[i].name}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            // The stack is as tall as the tallest visible plan;
            // AnimatedSize eases the height between plans of different
            // lengths while ClipRect hides the off-screen neighbours.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  _onDragUpdate(details, width),
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: _onDragCancel,
              child: Stack(
                children: [
                  for (var i = 0; i < widget.packages.length; i++)
                    (i - _page).abs() < 1
                        ? Transform.translate(
                            offset: Offset((i - _page) * width, 0),
                            child: SizedBox(
                              width: width,
                              child: _PlanDetailPanel(
                                key: ValueKey(_planKey(i)),
                                package: widget.packages[i],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full detail of the active plan — delivery, revisions, description and
/// features are all shown in full, never shortened or truncated.
class _PlanDetailPanel extends StatelessWidget {
  final ServicePackage package;

  const _PlanDetailPanel({super.key, required this.package});

  @override
  Widget build(BuildContext context) {
    final name = package.name.isNotEmpty
        ? package.name
        : package.tier.displayName;
    final revisionsLabel = package.revisions >= 99
        ? 'Unlimited revisions'
        : '${package.revisions} revision${package.revisions == 1 ? '' : 's'}';
    return Container(
      width: double.infinity,
      padding: context.rAll(20),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(18)),
        border: Border.all(
          color: package.isPopular ? AppTheme.accent : AppTheme.whisperBorder,
          width: package.isPopular ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (package.isPopular) ...[
            Text(
              'RECOMMENDED',
              style: TextStyle(
                fontSize: context.rsp(11),
                fontWeight: FontWeight.w800,
                color: AppTheme.accent,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: context.rh(6)),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: context.rsp(19),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                    height: 1.2,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(8),
                  vertical: context.rh(3),
                ),
                decoration: BoxDecoration(
                  color: package.isPopular
                      ? AppTheme.accent.withValues(alpha: 0.12)
                      : AppTheme.warmMist,
                  borderRadius: BorderRadius.circular(context.rr(8)),
                ),
                child: Text(
                  package.tier.displayName,
                  style: TextStyle(
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                    color: package.isPopular
                        ? AppTheme.accent
                        : AppTheme.mutedSteel,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(8)),
          Text(
            formatGhs(package.price),
            style: TextStyle(
              fontSize: context.rsp(22),
              fontWeight: FontWeight.w800,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(12)),
          _PlanDetailRow(
            icon: LucideIcons.clock,
            label: 'Delivery',
            value: package.deliveryTimeFormatted,
          ),
          SizedBox(height: context.rh(8)),
          _PlanDetailRow(
            icon: LucideIcons.refreshCw,
            label: 'Revisions',
            value: revisionsLabel,
          ),
          if (package.description.isNotEmpty) ...[
            SizedBox(height: context.rh(12)),
            Text(
              package.description,
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.charcoalInk,
                height: 1.5,
              ),
            ),
          ],
          SizedBox(height: context.rh(14)),
          const Divider(color: AppTheme.whisperBorder, height: 1),
          SizedBox(height: context.rh(14)),
          Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                size: context.ri(14),
                color: package.isPopular
                    ? AppTheme.accent
                    : AppTheme.mutedSteel,
              ),
              SizedBox(width: context.rw(6)),
              Expanded(
                child: Text(
                  '$name includes:',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(10)),
          if (package.features.isNotEmpty) ...[
            for (final feature in package.features)
              Padding(
                padding: EdgeInsets.only(bottom: context.rh(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: context.rh(2)),
                      child: Icon(
                        LucideIcons.check,
                        size: context.ri(15),
                        color: package.isPopular
                            ? AppTheme.accent
                            : AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(width: context.rw(8)),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          fontWeight: FontWeight.w500,
                          color: AppTheme.charcoalInk,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: context.rh(2)),
                  child: Icon(
                    LucideIcons.check,
                    size: context.ri(15),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(width: context.rw(8)),
                Expanded(
                  child: Text(
                    'Full delivery within ${package.deliveryTimeFormatted}',
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      fontWeight: FontWeight.w500,
                      color: AppTheme.charcoalInk,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One labeled package fact (delivery, revisions), always shown in full.
class _PlanDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PlanDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: context.ri(15), color: AppTheme.mutedSteel),
        SizedBox(width: context.rw(8)),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: context.rsp(13),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceVideoTile extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onTap;

  const _ServiceVideoTile({required this.videoUrl, required this.onTap});

  @override
  State<_ServiceVideoTile> createState() => _ServiceVideoTileState();
}

class _ServiceVideoTileState extends State<_ServiceVideoTile> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized)
            VideoPlayer(_controller!)
          else
            Container(color: Colors.black),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _initialized ? LucideIcons.play : LucideIcons.video,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
