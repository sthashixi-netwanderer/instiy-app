import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../models/service_model.dart';
import '../../services/service_service.dart';
import '../../providers/providers.dart';
import '../../widgets/service_review_section.dart';
import '../../widgets/media_viewer.dart';
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

  /// Index into the sorted packages list, or null while the customer
  /// hasn't picked a plan yet — contacting the provider requires an
  /// explicit selection so the quoted price matches what they chose.
  int? _selectedPackageIndex;
  int _galleryPage = 0;
  final GlobalKey _packagesKey = GlobalKey();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadService();
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
      setState(() {
        _service = service;
        _isLoading = false;
      });
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
      if (mounted) _loadService();
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
    if (_selectedPackageIndex != null && _selectedPackageIndex! >= packages.length) {
      _selectedPackageIndex = null;
    }
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
          Row(
            key: _packagesKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildSectionTitle('Plans & Packages'),
              if (packages.length > 1)
                Padding(
                  padding: EdgeInsets.only(bottom: context.rh(2)),
                  child: Text(
                    'Swipe to view all →',
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: context.rh(4)),
          Text(
            _selectedPackageIndex == null
                ? 'Select a plan to contact the provider.'
                : 'Selected: ${_planLabel(packages[_selectedPackageIndex!])}',
            style: TextStyle(
              fontSize: context.rsp(12),
              color: _selectedPackageIndex == null
                  ? AppTheme.mutedSteel
                  : AppTheme.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: context.rh(12)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < packages.length; i++) ...[
                  _PlanCard(
                    package: packages[i],
                    isSelected: _selectedPackageIndex == i,
                    isOwnService: _isOwnService,
                    onSelect: () => setState(() => _selectedPackageIndex = i),
                    // "Get started" doubles as the selection: tapping it on a
                    // card means the customer wants that specific package.
                    onAction: () {
                      setState(() => _selectedPackageIndex = i);
                      _contactProvider(context, ref, service);
                    },
                  ),
                  if (i < packages.length - 1)
                    SizedBox(width: context.rw(14)),
                ],
              ],
            ),
          ),
        ],
        SizedBox(height: context.rh(24)),
        if (service.providerName != null) _buildProviderCard(service),
        SizedBox(height: context.rh(24)),
        if (!_isOwnService)
          ShadButton(
            onPressed: () => _contactProvider(context, ref, service),
            child: Text(
              packages.isNotEmpty && _selectedPackageIndex == null
                  ? 'Select a Package to Continue'
                  : 'Contact Provider',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildGallery(Service service) {
    final images = service.imageUrls;
    if (images.isEmpty) {
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
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _galleryPage = i),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => MediaViewer.open(
                  context,
                  images,
                  initialIndex: index,
                ),
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  fit: BoxFit.cover,
                  memCacheWidth: 800,
                  placeholder: (_, _) => Container(color: AppTheme.warmMist),
                  errorWidget: (_, _, _) => Container(color: AppTheme.warmMist),
                ),
              ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          SizedBox(height: context.rh(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
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

  Widget _buildProviderCard(Service service) {
    return Container(
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
                  service.providerName!,
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
                if (service.providerPublicEmail != null &&
                    service.providerPublicEmail!.isNotEmpty) ...[
                  SizedBox(height: context.rh(6)),
                  Row(
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
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    foregroundColor: AppTheme.accent,
                    onPressed: () => _showProviderBioSheet(service),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (service.providerBio != null &&
                                  service.providerBio!.isNotEmpty)
                              ? 'Read full bio'
                              : 'About provider',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevronRight, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            if (hasEmail) ...[
              SizedBox(height: ctx.rh(16)),
              Row(
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
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _planLabel(ServicePackage package) {
    final name = package.name.isNotEmpty
        ? package.name
        : package.tier.displayName;
    return '$name — ${formatGhs(package.price)}';
  }

  /// Brings the Plans & Packages row into view so the customer sees the
  /// options they need to pick from.
  void _scrollToPackages() {
    final ctx = _packagesKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.1,
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

    // A package must be chosen explicitly so the chat quotes the exact
    // plan the customer wants. Services without any packages fall back to
    // the service-level starting price.
    final packages = service.sortedPackages;
    ServicePackage? selectedPackage;
    if (packages.isNotEmpty) {
      final index = _selectedPackageIndex;
      if (index == null || index >= packages.length) {
        _scrollToPackages();
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            title: Text('Select a package first'),
            description: Text(
              'Tap the plan you want, then contact the provider.',
            ),
          ),
        );
        return;
      }
      selectedPackage = packages[index];
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

class _PlanCard extends StatelessWidget {
  final ServicePackage package;
  final bool isSelected;
  final bool isOwnService;
  final VoidCallback onSelect;
  final VoidCallback onAction;

  const _PlanCard({
    required this.package,
    required this.isSelected,
    required this.isOwnService,
    required this.onSelect,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isPopular = package.isPopular;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: context.rw(290),
        padding: context.rAll(20),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(18)),
          border: Border.all(
            color: isPopular
                ? AppTheme.accent
                : (isSelected
                    ? AppTheme.accent.withValues(alpha: 0.8)
                    : AppTheme.whisperBorder),
            width: isPopular ? 2.0 : (isSelected ? 1.6 : 1.0),
          ),
          boxShadow: isPopular
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : (isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Badge / Header (RECOMMENDED / POPULAR)
            if (isPopular) ...[
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

            // Plan Title / Custom Package Name
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.name.isNotEmpty
                        ? package.name
                        : package.tier.displayName,
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
                    color: isPopular
                        ? AppTheme.accent.withValues(alpha: 0.12)
                        : AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Text(
                    package.tier.displayName,
                    style: TextStyle(
                      fontSize: context.rsp(10),
                      fontWeight: FontWeight.w600,
                      color: isPopular ? AppTheme.accent : AppTheme.mutedSteel,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(8)),

            // Delivery time pill (e.g. ⏱ 30 minutes, ⏱ 2 hours, ⏱ 3 days)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.rw(10),
                vertical: context.rh(4),
              ),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(10)),
                border: Border.all(
                  color: AppTheme.whisperBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.clock,
                    size: context.ri(13),
                    color: AppTheme.mutedSteel,
                  ),
                  SizedBox(width: context.rw(5)),
                  Text(
                    package.deliveryTimeFormatted,
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      fontWeight: FontWeight.w500,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.rh(14)),

            // Pricing & Revisions
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatGhs(package.price),
                  style: TextStyle(
                    fontSize: context.rsp(22),
                    fontWeight: FontWeight.w800,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(width: context.rw(6)),
                Text(
                  package.revisions >= 99
                      ? '• Unlimited revs'
                      : '• ${package.revisions} rev${package.revisions == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: context.rsp(11),
                    color: AppTheme.mutedSteel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (package.description.isNotEmpty) ...[
              SizedBox(height: context.rh(4)),
              Text(
                package.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.rsp(11),
                  color: AppTheme.mutedSteel,
                  height: 1.4,
                ),
              ),
            ],
            SizedBox(height: context.rh(14)),

            // Call to Action Button
            SizedBox(
              width: double.infinity,
              height: context.rh(40),
              child: isPopular
                  ? ShadButton(
                      onPressed: isOwnService ? onSelect : onAction,
                      child: Text(
                        isOwnService ? 'Select Plan' : 'Get started',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    )
                  : ShadButton.outline(
                      onPressed: isOwnService ? onSelect : onAction,
                      child: Text(
                        isOwnService ? 'Select Plan' : 'Get started',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppTheme.accent
                              : AppTheme.charcoalInk,
                        ),
                      ),
                    ),
            ),
            SizedBox(height: context.rh(16)),

            // Divider
            const Divider(color: AppTheme.whisperBorder, height: 1),
            SizedBox(height: context.rh(14)),

            // Features header
            Row(
              children: [
                Icon(
                  LucideIcons.sparkles,
                  size: context.ri(14),
                  color: isPopular ? AppTheme.accent : AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(6)),
                Expanded(
                  child: Text(
                    '${package.name.isNotEmpty ? package.name : package.tier.displayName} includes:',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

            // Features list (vertically arranged)
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
                          color: isPopular
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
              Padding(
                padding: EdgeInsets.only(bottom: context.rh(6)),
                child: Row(
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
              ),
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
                      package.revisions >= 99
                          ? 'Unlimited revisions included'
                          : '${package.revisions} revision${package.revisions == 1 ? '' : 's'} included',
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
      ),
    );
  }
}
