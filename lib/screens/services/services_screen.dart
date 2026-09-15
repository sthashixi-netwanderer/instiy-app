import 'dart:async';

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

/// Services marketplace hub: browse published services (search + category
/// filters). The creator dashboard (My Services) lives on the Dashboard
/// screen's Services tab.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _searchCtrl = TextEditingController();
  final _discoverScrollCtrl = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _discoverScrollCtrl.addListener(_onDiscoverScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = ref.read(serviceProvider);
      prov.loadServices();
      prov.loadCategories();
      prov.loadInstitutions();
    });
  }

  @override
  void dispose() {
    _discoverScrollCtrl.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Fetches the next page once the Discover grid nears its end — the
  /// marketplace arrives in chunks instead of one unbounded query. The
  /// provider ignores redundant calls, so no local guards are needed.
  void _onDiscoverScroll() {
    if (!_discoverScrollCtrl.hasClients) return;
    final position = _discoverScrollCtrl.position;
    if (position.pixels < position.maxScrollExtent * 0.8) return;
    ref.read(serviceProvider).loadMoreServices();
  }

  Future<void> _loadServices() async {
    // Silent: keeps the current results on screen while they refresh.
    await ref.read(serviceProvider).loadServices(silent: true);
  }

  /// Live search — results update shortly after the user stops typing.
  void _onSearchChanged(String value) {
    setState(() {}); // Refresh the clear-button visibility.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(serviceProvider).setSearchQuery(value.trim());
      _loadServices();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {});
    ref.read(serviceProvider).setSearchQuery('');
    _loadServices();
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
      ),
      body: Column(
        children: [
          SizedBox(
            height:
                MediaQuery.paddingOf(context).top +
                kToolbarHeight +
                context.rh(16),
          ),
          Expanded(
            child: _buildDiscoverTab(serviceProv),
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
                  trailing: _searchCtrl.text.isEmpty
                      ? null
                      : ShadIconButton.ghost(
                          width: context.ri(30),
                          height: context.ri(30),
                          icon: Icon(
                            LucideIcons.x,
                            size: context.ri(15),
                            color: AppTheme.mutedSteel,
                          ),
                          onPressed: _clearSearch,
                        ),
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: (value) {
                    // Submit skips the debounce and searches immediately.
                    _searchDebounce?.cancel();
                    ref.read(serviceProvider).setSearchQuery(value.trim());
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
          // Skeleton only on the very first load — while live-searching the
          // previous results stay visible until the new ones arrive.
          child: serviceProv.isLoading && services.isEmpty
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
                        controller: _discoverScrollCtrl,
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
                          childAspectRatio: 0.68,
                        ),
                        // The extra cell is a skeleton while another page
                        // can still be loaded.
                        itemCount: services.length +
                            (serviceProv.hasMoreServices ? 1 : 0),
                        itemBuilder: (context, index) =>
                            index == services.length
                                ? const ProductCardSkeleton()
                                : _ServiceCard(
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



  void _showInstitutionFilterSheet() {
    final prov = ref.read(serviceProvider);
    final allInstitutions = prov.institutions;
    final searchController = TextEditingController();
    showShadSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? allInstitutions
                : allInstitutions.where((inst) {
                    return inst.name.toLowerCase().contains(query) ||
                        inst.code.toLowerCase().contains(query);
                  }).toList();
            return ShadSheet(
              title: const Text('Filter by institution'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadInput(
                    controller: searchController,
                    placeholder: const Text(
                      'Search by name or shortcode (e.g. UG, KNUST)',
                    ),
                    leading: const Icon(LucideIcons.search, size: 18),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  SizedBox(height: context.rh(8)),
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.55,
                    child: ListView.builder(
                      itemCount: filtered.length + 1,
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
                        final institution = filtered[index - 1];
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
                            subtitle: institution.code.isNotEmpty
                                ? Text(
                                    institution.code.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: context.rsp(11),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  )
                                : null,
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
      },
    ).whenComplete(() => searchController.dispose());
  }












}

// ============================================================
// Widgets
// ============================================================

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
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(context.rw(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                  // Provider row — avatar + name (mirrors product cards).
                  if (service.providerName != null &&
                      service.providerName!.isNotEmpty)
                    Row(
                      children: [
                        ShadAvatar(
                          (service.providerAvatar != null &&
                                  service.providerAvatar!.isNotEmpty)
                              ? service.providerAvatar
                              : null,
                          size: Size(context.ri(18), context.ri(18)),
                          backgroundColor: AppTheme.accent,
                          placeholder: Text(
                            service.providerName![0].toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: context.rsp(8),
                            ),
                          ),
                        ),
                        SizedBox(width: context.rw(4)),
                        Expanded(
                          child: Text(
                            service.providerName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: context.rsp(11),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: context.rh(6)),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: context.ri(14),
                        color: (service.reviewCount != null &&
                                service.reviewCount! > 0)
                            ? const Color(0xFFF59E0B)
                            : AppTheme.mutedSteel.withValues(alpha: 0.4),
                      ),
                      SizedBox(width: context.rw(2)),
                      Text(
                        (service.reviewCount != null &&
                                service.reviewCount! > 0)
                            ? service.averageRating?.toStringAsFixed(1) ?? '5.0'
                            : 'New',
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          fontWeight: FontWeight.w600,
                          color: (service.reviewCount != null &&
                                  service.reviewCount! > 0)
                              ? AppTheme.charcoalInk
                              : AppTheme.mutedSteel,
                        ),
                      ),
                      if (service.reviewCount != null &&
                          service.reviewCount! > 0) ...[
                        SizedBox(width: context.rw(2)),
                        Text(
                          '(${service.reviewCount})',
                          style: TextStyle(
                            fontSize: context.rsp(10),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                      if (delivery != null || service.minDeliveryTimeFormatted != null) ...[
                        const Spacer(),
                        Icon(
                          LucideIcons.clock,
                          size: context.ri(11),
                          color: AppTheme.mutedSteel,
                        ),
                        SizedBox(width: context.rw(2)),
                        Text(
                          service.minDeliveryTimeFormatted != null
                              ? (service.minDeliveryTimeFormatted!.contains('minute')
                                  ? '${service.minDeliveryTimeFormatted!.split(' ').first}m'
                                  : (service.minDeliveryTimeFormatted!.contains('hour')
                                      ? '${service.minDeliveryTimeFormatted!.split(' ').first}h'
                                      : (service.minDeliveryTimeFormatted!.contains('month')
                                          ? '${service.minDeliveryTimeFormatted!.split(' ').first}mo'
                                          : (service.minDeliveryTimeFormatted!.contains('year')
                                              ? '${service.minDeliveryTimeFormatted!.split(' ').first}yr'
                                              : '${service.minDeliveryTimeFormatted!.split(' ').first}d'))))
                              : '${delivery}d',
                          style: TextStyle(
                            fontSize: context.rsp(10),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: context.rh(4)),
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
            ),
          ),
        ),
      ],
    ),
  ),
    );
  }
}

