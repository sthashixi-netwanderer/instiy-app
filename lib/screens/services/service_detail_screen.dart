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
  int _selectedPackageIndex = 0;
  int _galleryPage = 0;

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  Future<void> _loadService() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = await ServiceService.getService(widget.serviceId);
      if (!mounted) return;
      setState(() {
        _service = service;
        _isLoading = false;
        _selectedPackageIndex = 0;
        _galleryPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
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
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
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
    if (_selectedPackageIndex >= packages.length) _selectedPackageIndex = 0;
    return ListView(
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
          _buildSectionTitle('Packages'),
          SizedBox(height: context.rh(8)),
          for (var i = 0; i < packages.length; i++)
            _PackageCard(
              package: packages[i],
              selected: _selectedPackageIndex == i,
              onTap: () => setState(() => _selectedPackageIndex = i),
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
              itemBuilder: (context, index) => CachedNetworkImage(
                imageUrl: images[index],
                fit: BoxFit.cover,
                memCacheWidth: 800,
                placeholder: (_, _) => Container(color: AppTheme.warmMist),
                errorWidget: (_, _, _) => Container(color: AppTheme.warmMist),
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
    final delivery = service.minDeliveryDays;
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
            '$delivery day${delivery == 1 ? '' : 's'} delivery',
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
              ],
            ),
          ),
        ],
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
        'price': service.startingPrice,
        'image_url': service.imageUrls.isNotEmpty
            ? service.imageUrls.first
            : null,
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

class _PackageCard extends StatelessWidget {
  final ServicePackage package;
  final bool selected;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(bottom: context.rh(10)),
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.whisperBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(10),
                    vertical: context.rh(4),
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.accent
                        : AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(10)),
                  ),
                  child: Text(
                    package.tier.displayName,
                    style: TextStyle(
                      fontSize: context.rsp(11),
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppTheme.charcoalInk,
                    ),
                  ),
                ),
                if (package.isPopular) ...[
                  SizedBox(width: context.rw(8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.rw(8),
                      vertical: context.rh(4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(context.rr(10)),
                    ),
                    child: Text(
                      'Popular',
                      style: TextStyle(
                        fontSize: context.rsp(10),
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[800],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  formatGhs(package.price),
                  style: TextStyle(
                    fontSize: context.rsp(17),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
            if (package.name.isNotEmpty) ...[
              SizedBox(height: context.rh(8)),
              Text(
                package.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: context.rsp(14),
                  color: AppTheme.charcoalInk,
                ),
              ),
            ],
            if (package.description.isNotEmpty) ...[
              SizedBox(height: context.rh(4)),
              Text(
                package.description,
                style: TextStyle(
                  fontSize: context.rsp(12),
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
              ),
            ],
            SizedBox(height: context.rh(10)),
            Row(
              children: [
                Icon(
                  LucideIcons.clock,
                  size: context.ri(14),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(4)),
                Text(
                  '${package.deliveryDays}-day delivery',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
                SizedBox(width: context.rw(14)),
                Icon(
                  LucideIcons.refreshCw,
                  size: context.ri(14),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(4)),
                Text(
                  package.revisions >= 99
                      ? 'Unlimited revisions'
                      : '${package.revisions} revision'
                        '${package.revisions == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
