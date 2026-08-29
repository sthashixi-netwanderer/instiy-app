import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/adaptive_nav.dart';
import '../../models/service_model.dart';
import '../../providers/providers.dart';
import '../../providers/service_provider.dart';

/// Services marketplace hub — the only entry point to service creation.
/// - Discover: browse published services (search + category filters).
/// - My Services: creator dashboard, gated behind the provider opt-in
///   that also lives here.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _searchCtrl = TextEditingController();
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = ref.read(serviceProvider);
      prov.loadServices();
      prov.loadCategories();
      prov.loadInstitutions();
      if (ref.read(authProvider).isAuthenticated) {
        prov.checkServiceProviderStatus();
        prov.loadMyServices();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    await ref.read(serviceProvider).loadServices();
  }

  void _openService(Service service) {
    Navigator.of(context).pushNamed('/service-detail', arguments: service.id);
  }

  @override
  Widget build(BuildContext context) {
    final serviceProv = ref.watch(serviceProvider);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Services'),
        actions: [
          if (_selectedTab == 1 && serviceProv.isServiceProvider == true)
            Padding(
              padding: EdgeInsets.only(right: context.rw(8)),
              child: ShadButton(
                size: ShadButtonSize.sm,
                onPressed: () => Navigator.of(context).pushNamed(
                  '/create-service',
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 16),
                    SizedBox(width: 6),
                    Text('Create'),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height:
                MediaQuery.paddingOf(context).top +
                kToolbarHeight +
                context.rh(16),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
            child: Row(
              children: [
                _TabPill(
                  label: 'Discover',
                  icon: LucideIcons.compass,
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                SizedBox(width: context.rw(8)),
                _TabPill(
                  label: 'My Services',
                  icon: LucideIcons.briefcaseBusiness,
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(12)),
          Expanded(
            child: _selectedTab == 0
                ? _buildDiscoverTab(serviceProv)
                : _buildMyServicesTab(serviceProv),
          ),
        ],
      ),
      bottomNavigationBar: AdaptiveNav(
        currentIndex: ref.watch(shellTabProvider),
        onTabSelected: (i) => ref.read(shellTabProvider.notifier).state = i,
      ),
    );
  }

  // ------------------------------------------------------------
  // Discover
  // ------------------------------------------------------------

  Widget _buildDiscoverTab(ServiceProvider serviceProv) {
    final services = serviceProv.services;
    final institutionSelected = serviceProv.selectedInstitutionName != null;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
          child: Row(
            children: [
              Expanded(
                child: ShadInput(
                  controller: _searchCtrl,
                  placeholder: const Text('Search services...'),
                  leading: Icon(LucideIcons.search, size: context.ri(20)),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    ref.read(serviceProvider).setSearchQuery(value);
                    _loadServices();
                  },
                ),
              ),
              SizedBox(width: context.rw(8)),
              ShadIconButton.outline(
                icon: Badge(
                  isLabelVisible: institutionSelected,
                  child: Icon(
                    LucideIcons.building,
                    size: context.ri(18),
                    color: institutionSelected
                        ? AppTheme.accent
                        : AppTheme.mutedSteel,
                  ),
                ),
                onPressed: _showInstitutionFilterSheet,
              ),
            ],
          ),
        ),
        if (serviceProv.categories.isNotEmpty) ...[
          SizedBox(height: context.rh(12)),
          SizedBox(
            height: context.rh(36),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
              itemCount: serviceProv.categories.length + 1,
              separatorBuilder: (_, _) => SizedBox(width: context.rw(8)),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _CategoryPill(
                    label: 'All',
                    selected: serviceProv.selectedCategoryId == null,
                    onTap: () => ref.read(serviceProvider).setCategory(null),
                  );
                }
                final category = serviceProv.categories[index - 1];
                return _CategoryPill(
                  label: category.name,
                  selected:
                      serviceProv.selectedCategoryId == category.id,
                  onTap: () => ref
                      .read(serviceProvider)
                      .setCategory(category.id),
                );
              },
            ),
          ),
        ],
        SizedBox(height: context.rh(12)),
        Expanded(
          child: serviceProv.isLoading
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
                  child: const ListSkeleton(count: 6),
                )
              : services.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _loadServices,
                      child: ListView(
                        children: [_buildDiscoverEmptyState()],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadServices,
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          context.rw(16),
                          0,
                          context.rw(16),
                          context.rh(16),
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: services.length,
                        itemBuilder: (context, index) => _ServiceCard(
                          service: services[index],
                          onTap: () => _openService(services[index]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDiscoverEmptyState() {
    final hasFilters = ref.read(serviceProvider).selectedCategoryId != null ||
        ref.read(serviceProvider).searchQuery.isNotEmpty ||
        ref.read(serviceProvider).selectedInstitutionName != null;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.briefcaseBusiness,
              size: context.ri(64),
              color: Colors.grey[300],
            ),
            SizedBox(height: context.rh(16)),
            Text(
              hasFilters ? 'No services match' : 'No services yet',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(16),
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              hasFilters
                  ? 'Try a different search or category'
                  : 'Be the first to offer one',
              style: TextStyle(
                color: AppTheme.mutedSteel,
                fontSize: context.rsp(13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // My Services (creator dashboard — reachable only from this screen)
  // ------------------------------------------------------------

  Widget _buildMyServicesTab(ServiceProvider serviceProv) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) {
      return _buildSignInPrompt();
    }

    // Still checking opt-in status.
    if (serviceProv.isServiceProvider == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (serviceProv.isServiceProvider != true) {
      return _buildOptInCard(serviceProv);
    }

    final myServices = serviceProv.myServices;
    return serviceProv.myServicesLoading && myServices.isEmpty
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
            child: const ListSkeleton(count: 4),
          )
        : myServices.isEmpty
            ? ListView(
                padding: EdgeInsets.all(context.rw(16)),
                children: [_buildNoServicesState()],
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(serviceProvider).loadMyServices(),
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    context.rw(16),
                    0,
                    context.rw(16),
                    context.rh(16),
                  ),
                  itemCount: myServices.length,
                  separatorBuilder: (_, _) =>
                      SizedBox(height: context.rh(12)),
                  itemBuilder: (context, index) => _MyServiceCard(
                    service: myServices[index],
                    onTap: () => _openService(myServices[index]),
                    onEdit: () => Navigator.of(context).pushNamed(
                      '/create-service',
                      arguments: myServices[index],
                    ),
                    onToggleStatus: () => _toggleStatus(myServices[index]),
                    onDelete: () => _confirmDelete(myServices[index]),
                  ),
                ),
              );
  }

  void _showInstitutionFilterSheet() {
    final prov = ref.read(serviceProvider);
    showShadSheet(
      context: context,
      builder: (ctx) {
        return ShadSheet(
          title: const Text('Filter by institution'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: prov.institutions.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final selected =
                          prov.selectedInstitutionName == null;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: const Icon(LucideIcons.globe),
                          title: const Text('All institutions'),
                          trailing: selected
                              ? Icon(
                                  LucideIcons.check,
                                  size: context.ri(18),
                                  color: AppTheme.accent,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            ref.read(serviceProvider).setInstitution(null);
                          },
                        ),
                      );
                    }
                    final institution = prov.institutions[index - 1];
                    final selected =
                        prov.selectedInstitutionName == institution.name;
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: const Icon(LucideIcons.building),
                        title: Text(
                          institution.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? Icon(
                                LucideIcons.check,
                                size: context.ri(18),
                                color: AppTheme.accent,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          ref
                              .read(serviceProvider)
                              .setInstitution(institution.name);
                        },
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: context.rh(8)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.rw(24)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.lock,
              size: context.ri(48),
              color: Colors.grey[300],
            ),
            SizedBox(height: context.rh(12)),
            Text(
              'Sign in to manage services',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(15),
              ),
            ),
            SizedBox(height: context.rh(16)),
            ShadButton(
              onPressed: () => Navigator.of(context).pushNamed('/login'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptInCard(ServiceProvider serviceProv) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.rw(20)),
        child: Container(
          padding: context.rAll(20),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(20)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: context.rAll(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(context.rr(16)),
                  ),
                  child: Icon(
                    LucideIcons.sparkles,
                    size: context.ri(28),
                    color: AppTheme.accent,
                  ),
                ),
              ),
              SizedBox(height: context.rh(16)),
              Center(
                child: Text(
                  'Offer your services',
                  style: TextStyle(
                    fontSize: context.rsp(19),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
              SizedBox(height: context.rh(6)),
              Center(
                child: Text(
                  'Turn your skills into listings customers can browse and book.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.mutedSteel,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: context.rh(18)),
              _optInBenefit(LucideIcons.layers,
                  'Build tiered packages — Basic, Standard & Premium'),
              SizedBox(height: context.rh(10)),
              _optInBenefit(LucideIcons.clock,
                  'Set your delivery time and revision counts'),
              SizedBox(height: context.rh(10)),
              _optInBenefit(LucideIcons.messageSquare,
                  'Customers reach you through built-in chat'),
              SizedBox(height: context.rh(20)),
              SizedBox(
                width: double.infinity,
                child: ShadButton(
                  onPressed: serviceProv.optingIn
                      ? null
                      : () => _showProviderOptInSheet(),
                  child: serviceProv.optingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Become a Service Provider',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optInBenefit(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: context.ri(18), color: AppTheme.accent),
        SizedBox(width: context.rw(10)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: context.rsp(13),
              color: AppTheme.charcoalInk,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showProviderOptInSheet() async {
    final confirmed = await showShadSheet<bool>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Become a Service Provider'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: context.rh(4)),
            Text(
              'You\'ll be able to create service listings, package them into '
              'tiers and manage them from this screen. This can\'t be undone '
              'later.',
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
                height: 1.5,
              ),
            ),
            SizedBox(height: context.rh(18)),
            Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(width: context.rw(12)),
                Expanded(
                  child: ShadButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Opt in'),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(8)),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await ref.read(serviceProvider).becomeServiceProvider();
    if (!mounted) return;
    if (result == true) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('You\'re a service provider now — create your first listing!'),
        ),
      );
    } else {
      ShadToaster.of(context).show(
        ShadToast(title: Text('Opt-in failed: $result')),
      );
    }
  }

  Widget _buildNoServicesState() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.45,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.packagePlus,
              size: context.ri(56),
              color: Colors.grey[300],
            ),
            SizedBox(height: context.rh(16)),
            Text(
              'No listings yet',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(16),
              ),
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'Create your first service and start getting customers',
              style: TextStyle(
                color: AppTheme.mutedSteel,
                fontSize: context.rsp(13),
              ),
            ),
            SizedBox(height: context.rh(16)),
            ShadButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/create-service'),
              child: const Text('Create a service'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStatus(Service service) async {
    final newStatus = service.isActive
        ? ServiceStatus.paused
        : ServiceStatus.active;
    final ok = await ref
        .read(serviceProvider)
        .setServiceStatus(service.id, newStatus);
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(
          ok
              ? (newStatus == ServiceStatus.active
                    ? 'Service published'
                    : 'Service paused')
              : 'Couldn\'t update the service',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Service service) async {
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Delete service'),
      description: Text(
        '"${service.title}" will be removed permanently. This cannot be undone.',
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton(
          backgroundColor: AppTheme.destructive,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref.read(serviceProvider).deleteService(service.id);
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(ok ? 'Service deleted' : 'Couldn\'t delete the service'),
      ),
    );
  }
}

// ============================================================
// Widgets
// ============================================================

class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(12),
          vertical: context.rh(9),
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.4)
                : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: context.ri(16),
              color: selected ? AppTheme.accent : AppTheme.mutedSteel,
            ),
            SizedBox(width: context.rw(6)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.rsp(13),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppTheme.accent : AppTheme.mutedSteel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(14),
          vertical: context.rh(8),
        ),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(20)),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.whisperBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: context.rsp(12),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppTheme.mutedSteel,
          ),
        ),
      ),
    );
  }
}

/// Fiverr-style grid card for the Discover tab.
class _ServiceCard extends StatelessWidget {
  final Service service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final delivery = service.minDeliveryDays;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.25,
              child: service.imageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: service.imageUrls.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) =>
                          Container(color: AppTheme.warmMist),
                    )
                  : Container(
                      color: AppTheme.warmMist,
                      child: Center(
                        child: Icon(
                          LucideIcons.image,
                          size: context.ri(26),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(context.rw(10)),
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
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: context.rh(4)),
                  if (service.providerName != null)
                    Text(
                      service.providerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  SizedBox(height: context.rh(6)),
                  Row(
                    children: [
                      if (service.reviewCount != null &&
                          service.reviewCount! > 0) ...[
                        Icon(
                          Icons.star,
                          size: context.ri(13),
                          color: Colors.amber,
                        ),
                        SizedBox(width: context.rw(3)),
                        Text(
                          service.averageRating?.toStringAsFixed(1) ?? '0.0',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: context.rw(3)),
                        Text(
                          '(${service.reviewCount})',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        'From ${formatGhs(service.startingPrice)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: context.rsp(12),
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                  if (delivery != null) ...[
                    SizedBox(height: context.rh(6)),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.clock,
                          size: context.ri(12),
                          color: AppTheme.mutedSteel,
                        ),
                        SizedBox(width: context.rw(3)),
                        Text(
                          '${delivery}d delivery',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row card for the creator's dashboard list.
class _MyServiceCard extends StatelessWidget {
  final Service service;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _MyServiceCard({
    required this.service,
    required this.onTap,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  Color _statusColor(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.active:
        return AppTheme.successMoss;
      case ServiceStatus.paused:
        return Colors.orange;
      case ServiceStatus.inactive:
        return AppTheme.mutedSteel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: context.rAll(12),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(context.rr(10)),
              child: SizedBox(
                width: context.rw(64),
                height: context.rh(64),
                child: service.imageUrls.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: service.imageUrls.first,
                        fit: BoxFit.cover,
                        memCacheWidth: 128,
                        placeholder: (_, _) =>
                            Container(color: AppTheme.warmMist),
                        errorWidget: (_, _, _) =>
                            Container(color: AppTheme.warmMist),
                      )
                    : Container(
                        color: AppTheme.warmMist,
                        child: Icon(
                          LucideIcons.image,
                          size: context.ri(22),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(4)),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(3),
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(service.status).withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Text(
                          service.status.displayName,
                          style: TextStyle(
                            fontSize: context.rsp(10),
                            fontWeight: FontWeight.w600,
                            color: _statusColor(service.status),
                          ),
                        ),
                      ),
                      SizedBox(width: context.rw(8)),
                      Text(
                        'From ${formatGhs(service.startingPrice)}',
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                  if (service.packages.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: context.rh(4)),
                      child: Text(
                        '${service.packages.length} package'
                        '${service.packages.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: context.rw(8)),
            GestureDetector(
              onTap: () => _showActionsMenu(context),
              child: Container(
                padding: context.rAll(6),
                child: Icon(
                  LucideIcons.moreVertical,
                  size: context.ri(18),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionsMenu(BuildContext context) {
    showShadSheet(
      context: context,
      builder: (ctx) => ShadSheet(
        title: Text(
          service.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Edit listing'),
              onTap: () {
                Navigator.of(ctx).pop();
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(
                service.isActive ? LucideIcons.pause : LucideIcons.play,
              ),
              title: Text(service.isActive ? 'Pause' : 'Publish'),
              onTap: () {
                Navigator.of(ctx).pop();
                onToggleStatus();
              },
            ),
            ListTile(
              leading: const Icon(
                LucideIcons.trash2,
                color: AppTheme.destructive,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: AppTheme.destructive),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                onDelete();
              },
            ),
            SizedBox(height: context.rh(8)),
          ],
        ),
      ),
    );
  }
}
