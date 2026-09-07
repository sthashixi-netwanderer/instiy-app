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
import '../../widgets/ai_enhance_button.dart';
import '../../widgets/required_label.dart';
import '../../widgets/user_avatar_menu.dart';
import '../../models/service_model.dart';
import '../../models/service_draft_model.dart';
import '../../models/notification_model.dart';
import '../../services/ai_service.dart';
import '../../services/service_draft_service.dart';
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
  final _appealCtrl = TextEditingController();
  int _selectedTab = 0;
  Timer? _searchDebounce;

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
        prov.loadPublishingServiceDraft();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _appealCtrl.dispose();
    super.dispose();
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

  /// Opens the create wizard unless a fire-and-forget publish is still in
  /// flight — the single draft slot can't track a second concurrent publish.
  void _openCreateService() {
    final draft = ref.read(serviceProvider).publishingServiceDraft;
    if (draft != null && draft.status == ServiceDraftStatus.publishing) {
      ShadToaster.of(context).show(
        const ShadToast(
          title:
              Text('Please wait for the current service to finish publishing'),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed('/create-service');
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
              padding: EdgeInsets.only(right: context.rw(4)),
              child: ShadButton(
                size: ShadButtonSize.sm,
                onPressed: _openCreateService,
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
          Builder(
            builder: (context) {
              final unreadServiceNotifs = ref
                  .watch(messageProvider)
                  .unreadServiceNotificationsCount;
              return Padding(
                padding: EdgeInsets.only(right: context.rw(8)),
                child: BadgeIconButton(
                  icon: LucideIcons.bell,
                  count: unreadServiceNotifs,
                  activeColor: AppTheme.accent,
                  onPressed: () {
                    final auth = ref.read(authProvider);
                    if (!auth.isAuthenticated) {
                      Navigator.of(context).pushNamed('/login');
                      return;
                    }
                    Navigator.of(context).pushNamed(
                      '/notifications',
                      arguments: NotificationScope.services,
                    );
                  },
                ),
              );
            },
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
      if (serviceProv.isProviderDisabled) {
        return _buildDisabledProviderState(serviceProv);
      }
      return _buildOptInCard(serviceProv);
    }

    final myServices = serviceProv.myServices;
    final publishDraft = serviceProv.publishingServiceDraft;
    return serviceProv.myServicesLoading && myServices.isEmpty
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
            child: const ListSkeleton(count: 4),
          )
        : myServices.isEmpty
            ? ListView(
                padding: EdgeInsets.all(context.rw(16)),
                children: [
                  if (publishDraft != null) ...[
                    _buildServicePublishStatusCard(
                      publishDraft,
                      serviceProv.publishProgress,
                    ),
                    SizedBox(height: context.rh(12)),
                  ],
                  _buildProviderBioCard(serviceProv),
                  SizedBox(height: context.rh(12)),
                  _buildProviderPublicEmailCard(serviceProv),
                  SizedBox(height: context.rh(12)),
                  _buildNoServicesState(),
                ],
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
                  itemCount: myServices.length + 1,
                  separatorBuilder: (_, _) =>
                      SizedBox(height: context.rh(12)),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (publishDraft != null) ...[
                            _buildServicePublishStatusCard(
                              publishDraft,
                              serviceProv.publishProgress,
                            ),
                            SizedBox(height: context.rh(12)),
                          ],
                          _buildProviderBioCard(serviceProv),
                          SizedBox(height: context.rh(12)),
                          _buildProviderPublicEmailCard(serviceProv),
                        ],
                      );
                    }
                    final service = myServices[index - 1];
                    return _MyServiceCard(
                      service: service,
                      onTap: () => _openService(service),
                      onEdit: () => Navigator.of(context).pushNamed(
                        '/create-service',
                        arguments: service,
                      ),
                      onToggleStatus: () => _toggleStatus(service),
                      onDelete: () => _confirmDelete(service),
                    );
                  },
                ),
              );
  }

  /// Live status of the fire-and-forget service publish — progress while
  /// uploading, error + retry when it failed (mirrors the profile screen's
  /// product publish card).
  Widget _buildServicePublishStatusCard(
    ServiceDraftListing draft,
    double progress,
  ) {
    final isPublishing = draft.status == ServiceDraftStatus.publishing;

    if (isPublishing) {
      return Container(
        padding: EdgeInsets.all(context.rw(16)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rw(16)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTheme.charcoalInk),
                  ),
                ),
                SizedBox(width: context.rw(12)),
                Expanded(
                  child: Text(
                    'Publishing "${draft.title}"...',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.charcoalInk,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(12)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: AppTheme.whisperBorder,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.charcoalInk),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(context.rw(16)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(context.rw(16)),
        border: Border.all(color: const Color(0xFFFEB2B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.alertTriangle,
                color: Color(0xFFC53030),
                size: 20,
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Failed to publish "${draft.title}"',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF9B2C2C),
                      ),
                    ),
                    SizedBox(height: context.rh(4)),
                    Text(
                      draft.errorMessage ??
                          'An unknown error occurred during publication.',
                      style: const TextStyle(
                        color: Color(0xFFC53030),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: context.rw(8),
            children: [
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () async {
                  await ServiceDraftService.clearDraft();
                  ref.read(serviceProvider).updatePublishingServiceDraft(null);
                },
                child: const Text('Dismiss'),
              ),
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: _openCreateService,
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  Widget _buildDisabledProviderState(ServiceProvider serviceProv) {
    final appeal = serviceProv.latestAppeal;
    final isPending = appeal != null && appeal['status'] == 'pending';
    DateTime? createdAt;
    if (appeal != null && appeal['created_at'] != null) {
      try {
        createdAt = DateTime.parse(appeal['created_at'].toString()).toLocal();
      } catch (_) {}
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.rw(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Disabled alert container
          Container(
            padding: context.rAll(18),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(16)),
              border: Border.all(
                color: AppTheme.destructive.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.charcoalInk.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: context.rAll(12),
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.shieldAlert,
                    size: context.ri(32),
                    color: AppTheme.destructive,
                  ),
                ),
                SizedBox(height: context.rh(14)),
                Text(
                  'Service Account Disabled',
                  style: TextStyle(
                    fontSize: context.rsp(18),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(6)),
                Text(
                  'Your service provider account has been disabled by an administrator. '
                  'Your listings are currently hidden from the marketplace and you cannot '
                  'create or edit services.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.mutedSteel,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(16)),

          if (isPending) ...[
            // Status banner for already submitted complaint
            Container(
              padding: context.rAll(16),
              decoration: BoxDecoration(
                color: AppTheme.warningAmber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(context.rr(14)),
                border: Border.all(
                  color: AppTheme.warningAmber.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.clock,
                        size: context.ri(18),
                        color: AppTheme.warningAmber,
                      ),
                      SizedBox(width: context.rw(8)),
                      Expanded(
                        child: Text(
                          'Complaint Under Review',
                          style: TextStyle(
                            fontSize: context.rsp(14),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(3),
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warningAmber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(context.rr(10)),
                        ),
                        child: Text(
                          'Pending',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.rh(10)),
                  Text(
                    'Your complaint has been submitted to the administration team for review. '
                    'Please keep watch in your email for updates regarding your account.',
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.charcoalInk,
                      height: 1.4,
                    ),
                  ),
                  if (createdAt != null) ...[
                    SizedBox(height: context.rh(4)),
                    Text(
                      'Submitted on ${createdAt.month}/${createdAt.day}/${createdAt.year}',
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  ],
                  if (appeal['complaint_text'] != null) ...[
                    SizedBox(height: context.rh(10)),
                    Container(
                      width: double.infinity,
                      padding: context.rAll(12),
                      decoration: BoxDecoration(
                        color: AppTheme.pureSurface,
                        borderRadius: BorderRadius.circular(context.rr(10)),
                        border: Border.all(color: AppTheme.whisperBorder),
                      ),
                      child: Text(
                        appeal['complaint_text'] as String,
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          color: AppTheme.charcoalInk,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Complaint submission box
            Container(
              padding: context.rAll(18),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(context.rr(16)),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit a Complaint or Appeal',
                    style: TextStyle(
                      fontSize: context.rsp(15),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(4)),
                  Text(
                    'Explain why your service provider account should be re-enabled. '
                    'This complaint will be sent directly to the administrative review team.',
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: context.rh(12)),
                  ShadInput(
                    controller: _appealCtrl,
                    placeholder: const Text(
                      'Describe your situation or reasons for appeal...',
                    ),
                    maxLines: 5,
                    maxLength: 500,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: context.rh(6)),
                  AiEnhanceButton(
                    controller: _appealCtrl,
                    enhance: AIService.enhanceProviderBio,
                  ),
                  SizedBox(height: context.rh(14)),
                  SizedBox(
                    width: double.infinity,
                    child: ShadButton(
                      enabled: _appealCtrl.text.trim().isNotEmpty &&
                          !serviceProv.appealSubmitting,
                      onPressed: () async {
                        final text = _appealCtrl.text.trim();
                        if (text.isEmpty) return;
                        final ok = await ref
                            .read(serviceProvider)
                            .submitAppeal(text);
                        if (!mounted) return;
                        if (ok) {
                          _appealCtrl.clear();
                          ShadToaster.of(context).show(
                            const ShadToast(
                              title: Text('Complaint submitted'),
                              description: Text(
                                'Your complaint has been submitted for review. Please check your email for updates.',
                              ),
                            ),
                          );
                        } else {
                          ShadToaster.of(context).show(
                            ShadToast.destructive(
                              title: const Text('Submission failed'),
                              description: Text(
                                serviceProv.error ??
                                    'Could not submit complaint. Please try again.',
                              ),
                            ),
                          );
                        }
                      },
                      child: serviceProv.appealSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.send, size: 16),
                                SizedBox(width: 8),
                                Text('Submit for Review'),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
    final bioCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final accountEmail = ref.read(authProvider).user?.email ?? '';
    var useAccountEmail = true;
    void Function(void Function())? sheetSetState;
    void onBioChanged() {
      sheetSetState?.call(() {});
    }
    bioCtrl.addListener(onBioChanged);

    final confirmed = await showShadSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          sheetSetState = setSheetState;
          final publicEmail =
              useAccountEmail ? accountEmail : emailCtrl.text.trim();
          final emailOk = useAccountEmail
              ? accountEmail.isNotEmpty
              : publicEmail.isNotEmpty;
          final canOptIn = bioCtrl.text.trim().isNotEmpty && emailOk;
          return ShadSheet(
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
                SizedBox(height: context.rh(16)),
                RequiredLabel(
                  'Tell customers about your services',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(14),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  'Shown under your name on every listing you create',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                ShadInput(
                  controller: bioCtrl,
                  placeholder: const Text(
                    'e.g. Graphic designer with 3 years of experience in '
                    'branding and logos',
                  ),
                  maxLines: 4,
                  maxLength: 300,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => setSheetState(() {}),
                ),
                SizedBox(height: context.rh(8)),
                // AI enhancer — bottom-right of the bio field.
                AiEnhanceButton(
                  controller: bioCtrl,
                  enhance: AIService.enhanceProviderBio,
                ),
                SizedBox(height: context.rh(16)),
                Text(
                  'Public contact email',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(14),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  'Shown on your listings so customers can reach you',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(12),
                    vertical: context.rh(10),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(10)),
                  ),
                  child: Text(
                    'Your Instiy account email: ${accountEmail.isEmpty ? '—' : accountEmail}',
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Row(
                  children: [
                    ShadCheckbox(
                      value: useAccountEmail,
                      onChanged: (v) =>
                          setSheetState(() => useAccountEmail = v),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(
                          () => useAccountEmail = !useAccountEmail,
                        ),
                        child: Text(
                          'Use my Instiy account email as my public email',
                          style: TextStyle(
                            fontSize: context.rsp(13),
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!useAccountEmail) ...[
                  SizedBox(height: context.rh(8)),
                  ShadInput(
                    controller: emailCtrl,
                    placeholder: const Text('e.g. contact@mydomain.com'),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setSheetState(() {}),
                  ),
                ],
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
                        onPressed: canOptIn
                            ? () => Navigator.of(ctx).pop(true)
                            : null,
                        child: const Text('Opt in'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.rh(8)),
              ],
            ),
          );
        },
      ),
    );

    bioCtrl.removeListener(onBioChanged);
    if (confirmed != true || !mounted) {
      bioCtrl.dispose();
      emailCtrl.dispose();
      return;
    }

    final publicEmail =
        useAccountEmail ? accountEmail : emailCtrl.text.trim();
    final result = await ref
        .read(serviceProvider)
        .becomeServiceProvider(
          bioCtrl.text,
          publicEmail.isEmpty ? null : publicEmail,
        );
    bioCtrl.dispose();
    emailCtrl.dispose();
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

  /// Compact card at the top of the My Services tab showing (and letting
  /// the provider edit) the bio that appears on their listings.
  Widget _buildProviderBioCard(ServiceProvider serviceProv) {
    final bio = serviceProv.providerBio;
    final hasBio = bio != null && bio.isNotEmpty;
    return Container(
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(14)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: context.rAll(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(
              LucideIcons.user,
              size: context.ri(18),
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Provider profile',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: context.rsp(14),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showEditProviderBioSheet,
                      child: Container(
                        padding: context.rAll(6),
                        child: Icon(
                          LucideIcons.pencil,
                          size: context.ri(16),
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  hasBio
                      ? bio
                      : 'Add a short bio so customers know what you offer',
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: hasBio
                        ? AppTheme.charcoalInk
                        : AppTheme.mutedSteel,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProviderBioSheet() async {
    final bioCtrl = TextEditingController(
      text: ref.read(serviceProvider).providerBio ?? '',
    );
    final confirmed = await showShadSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ShadSheet(
          title: const Text('Edit provider bio'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: context.rh(4)),
              ShadInput(
                controller: bioCtrl,
                placeholder: const Text(
                  'Describe the services you offer...',
                ),
                maxLines: 5,
                maxLength: 300,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setSheetState(() {}),
              ),
              SizedBox(height: context.rh(8)),
              // AI enhancer — bottom-right of the bio field.
              AiEnhanceButton(
                controller: bioCtrl,
                enhance: AIService.enhanceProviderBio,
              ),
              SizedBox(height: context.rh(14)),
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
                      onPressed: bioCtrl.text.trim().isNotEmpty
                          ? () => Navigator.of(ctx).pop(true)
                          : null,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rh(8)),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      bioCtrl.dispose();
      return;
    }

    final result = await ref
        .read(serviceProvider)
        .updateProviderBio(bioCtrl.text);
    bioCtrl.dispose();
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(
          switch (result) {
            ProviderBioSaveResult.saved => 'Provider bio updated',
            ProviderBioSaveResult.savedLocally =>
              'Saved on this device — it will sync to your account once a '
                  'pending database update lands',
            ProviderBioSaveResult.failed =>
              'Couldn\'t update your bio',
          },
        ),
      ),
    );
  }

  Widget _buildProviderPublicEmailCard(ServiceProvider serviceProv) {
    final email = serviceProv.providerEmail;
    final hasEmail = email != null && email.isNotEmpty;
    return Container(
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(14)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: context.rAll(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(
              LucideIcons.mail,
              size: context.ri(18),
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Public contact email',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: context.rsp(14),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showEditProviderPublicEmailSheet,
                      child: Container(
                        padding: context.rAll(6),
                        child: Icon(
                          LucideIcons.pencil,
                          size: context.ri(16),
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  hasEmail
                      ? email
                      : 'Add a public email so customers can reach you',
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: hasEmail
                        ? AppTheme.charcoalInk
                        : AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProviderPublicEmailSheet() async {
    final accountEmail = ref.read(authProvider).user?.email ?? '';
    final currentEmail = ref.read(serviceProvider).providerEmail;
    // Default to the account email when no custom one has been set (or the
    // custom one already matches it).
    var useAccountEmail = currentEmail == null ||
        currentEmail.isEmpty ||
        currentEmail == accountEmail;
    final emailCtrl = TextEditingController(
      text: useAccountEmail ? '' : currentEmail,
    );
    final confirmed = await showShadSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ShadSheet(
          title: const Text('Edit public email'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: context.rh(4)),
              Text(
                'Shown on your listings so customers can contact you.',
                style: TextStyle(
                  fontSize: context.rsp(13),
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
              ),
              SizedBox(height: context.rh(12)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(12),
                  vertical: context.rh(10),
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warmMist,
                  borderRadius: BorderRadius.circular(context.rr(10)),
                ),
                child: Text(
                  'Your Instiy account email: ${accountEmail.isEmpty ? '—' : accountEmail}',
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ),
              SizedBox(height: context.rh(8)),
              Row(
                children: [
                  ShadCheckbox(
                    value: useAccountEmail,
                    onChanged: (v) =>
                        setSheetState(() => useAccountEmail = v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setSheetState(
                        () => useAccountEmail = !useAccountEmail,
                      ),
                      child: Text(
                        'Use my Instiy account email as my public email',
                        style: TextStyle(
                          fontSize: context.rsp(13),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!useAccountEmail) ...[
                SizedBox(height: context.rh(8)),
                ShadInput(
                  controller: emailCtrl,
                  placeholder: const Text('e.g. contact@mydomain.com'),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setSheetState(() {}),
                ),
              ],
              SizedBox(height: context.rh(14)),
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
                      // Saving the account email needs one to exist; a
                      // custom email may be emptied to clear the public
                      // email from listings.
                      onPressed: (!useAccountEmail ||
                              accountEmail.isNotEmpty)
                          ? () => Navigator.of(ctx).pop(true)
                          : null,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rh(8)),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      emailCtrl.dispose();
      return;
    }

    final publicEmail = useAccountEmail ? accountEmail : emailCtrl.text;
    final result = await ref
        .read(serviceProvider)
        .updateProviderEmail(publicEmail);
    emailCtrl.dispose();
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(
          switch (result) {
            ProviderEmailSaveResult.saved => 'Public email updated',
            ProviderEmailSaveResult.savedLocally =>
              'Saved on this device — it will sync to your account once a '
                  'pending database update lands',
            ProviderEmailSaveResult.failed =>
              'Couldn\'t update your email',
          },
        ),
      ),
    );
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
              onPressed: _openCreateService,
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
    if (newStatus == ServiceStatus.active &&
        ref.read(serviceProvider).isServiceProvider != true) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          title: Text('Provider access required'),
          description: Text(
            'Your service provider status is disabled. You cannot publish services.',
          ),
        ),
      );
      return;
    }
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
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: context.ri(16),
              color: selected ? AppTheme.accent : AppTheme.mutedSteel,
            ),
            SizedBox(width: context.rw(6)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.rsp(13),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppTheme.accent : AppTheme.mutedSteel,
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
                            ? '${service.averageRating?.toStringAsFixed(1)} (${service.reviewCount})'
                            : 'New',
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          color: AppTheme.mutedSteel,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.rh(4)),
                  Row(
                    children: [
                      Text(
                        'From ${formatGhs(service.startingPrice)}',
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                      if (service.packages.isNotEmpty) ...[
                        SizedBox(width: context.rw(8)),
                        Text(
                          '•  ${service.packages.length} package'
                          '${service.packages.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ],
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
        child: Material(
          color: Colors.transparent,
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
                title: const Text(
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
      ),
    );
  }
}
