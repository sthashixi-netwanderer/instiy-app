import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';
import '../../models/service_model.dart';
import '../../services/service_service.dart';
import '../../providers/providers.dart';
import '../messages/messages_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Service> _services = [];
  bool _isLoading = true;
  String _searchQuery = '';

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    setState(() => _isLoading = true);
    try {
      final services = await ServiceService.getServices(
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) setState(() => _services = services);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Services')),
      body: Stack(
        children: [
          // Content extends behind the search bar
          Positioned.fill(
            child: _isLoading
                ? Padding(
                    padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 72, 16, 16),
                    child: const ListSkeleton(count: 6),
                  )
                : _services.isEmpty
                    ? Padding(
                        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight + 72),
                        child: _buildEmptyState(),
                      )
                    : RefreshIndicator(
                        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + 56,
                        onRefresh: _loadServices,
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 72, 16, 16),
                          itemCount: _services.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: context.rh(12)),
                          itemBuilder: (context, index) {
                            return _ServiceCard(
                              service: _services[index],
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _ServiceDetailScreen(service: _services[index]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          // Floating search bar (transparent to content behind)
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(8),
            left: context.rw(16),
            right: context.rw(16),
            child: Material(
              color: Colors.transparent,
              child: ShadInput(
                controller: _searchCtrl,
                placeholder: const Text('Search services...'),
                leading: Icon(LucideIcons.search, size: context.ri(20)),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  setState(() => _searchQuery = value);
                  _loadServices();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.wrench,
              size: context.ri(64), color: Colors.grey[300]),
          SizedBox(height: context.rh(16)),
          Text('No services found',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.rsp(16))),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Service service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(context.rr(12)),
              child: SizedBox(
                width: context.rw(72),
                height: context.rh(72),
                child: service.imageUrls.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: service.imageUrls.first,
                    fit: BoxFit.cover,
                    memCacheWidth: 72,
                    placeholder: (_, _) =>
                        Container(color: AppTheme.warmMist),
                    errorWidget: (_, _, _) =>
                        Container(color: AppTheme.warmMist),
                  )
                    : Container(
                        color: AppTheme.warmMist,
                        child: Icon(LucideIcons.image, size: context.ri(24), color: AppTheme.mutedSteel),
                      ),
              ),
            ),
            SizedBox(width: context.rw(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.title,
                    maxLines: 2,
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
                      if (service.averageRating != null) ...[
                        Icon(Icons.star, size: context.ri(14), color: Colors.amber),
                        SizedBox(width: context.rw(4)),
                        Text(
                          service.averageRating!.toStringAsFixed(1),
                          style: TextStyle(fontSize: context.rsp(12)),
                        ),
                        if (service.reviewCount != null) ...[
                          SizedBox(width: context.rw(4)),
                          Text(
                            '(${service.reviewCount})',
                            style: TextStyle(
                              fontSize: context.rsp(12),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                        const Spacer(),
                      ],
                      Text(
                        'GH\u00a2 ${service.price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: context.rsp(14),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    ],
                  ),
                  if (service.providerName != null)
                    Padding(
                      padding: EdgeInsets.only(top: context.rh(4)),
                      child: Text(
                        'by ${service.providerName}',
                        style: TextStyle(
                          fontSize: context.rsp(12),
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceDetailScreen extends ConsumerWidget {
  final Service service;

  const _ServiceDetailScreen({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: Text(service.title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(16), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16), context.rw(16), context.rh(16)),
        children: [
          if (service.imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(context.rr(16)),
              child: SizedBox(
                height: context.rh(220),
                width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: service.imageUrls.first,
                fit: BoxFit.cover,
                memCacheWidth: 220,
                placeholder: (_, _) =>
                    Container(color: AppTheme.warmMist),
                errorWidget: (_, _, _) =>
                    Container(color: AppTheme.warmMist),
              ),
              ),
            ),
          SizedBox(height: context.rh(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  service.title,
                  style: TextStyle(
                    fontSize: context.rsp(22),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
              Text(
                'GH\u00a2 ${service.price.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: context.rsp(22),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(8)),
          if (service.averageRating != null)
            Row(
              children: [
                Icon(Icons.star, size: context.ri(18), color: Colors.amber),
                SizedBox(width: context.rw(4)),
                Text(
                  service.averageRating!.toStringAsFixed(1),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.rsp(14)),
                ),
                if (service.reviewCount != null) ...[
                  SizedBox(width: context.rw(4)),
                  Text(
                    '(${service.reviewCount} reviews)',
                    style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(14)),
                  ),
                ],
              ],
            ),
          SizedBox(height: context.rh(16)),
          Text(
            'Description',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: context.rsp(16),
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            service.description ?? 'No description provided.',
            style: TextStyle(
              color: AppTheme.mutedSteel,
              height: 1.5,
              fontSize: context.rsp(14),
            ),
          ),
          SizedBox(height: context.rh(24)),
          if (service.providerName != null)
            Container(
              padding: context.rAll(16),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(12)),
              ),
              child: Row(
                children: [
                  ShadAvatar(
                    (service.providerAvatar != null && service.providerAvatar!.isNotEmpty)
                        ? service.providerAvatar
                        : null,
                    backgroundColor: AppTheme.accent,
                    placeholder: Text(
                      (service.providerName ?? 'S')[0].toUpperCase(),
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.rsp(14)),
                    ),
                  ),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.providerName!,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.rsp(14)),
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
            ),
          SizedBox(height: context.rh(32)),
          ShadButton(
            onPressed: () => _contactProvider(context, ref),
            child: const Text('Contact Provider',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _contactProvider(BuildContext context, WidgetRef ref) async {
    final authProv = ref.read(authProvider);
    if (!authProv.isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }

    final buyerId = authProv.user!.id;
    final providerId = service.providerId;

    if (buyerId == providerId) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text("You cannot contact yourself.")),
      );
      return;
    }

    // Show a loading indicator
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final msgProv = ref.read(messageProvider);

      // Pass the service details as productReference so they know what service is referred to
      final serviceRef = {
        'product_id': service.id,
        'title': service.title,
        'price': service.price,
        'image_url': service.imageUrls.isNotEmpty ? service.imageUrls.first : null,
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
