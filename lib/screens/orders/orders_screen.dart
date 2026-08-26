import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/order_model.dart';
import '../../services/wallet_lock_service.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _isLocked = true;
  bool _checkingLock = true;
  final TextEditingController _pendingSearchController =
      TextEditingController();
  final TextEditingController _completedSearchController =
      TextEditingController();
  String _pendingQuery = '';
  String _completedQuery = '';
  Timer? _pendingSearchDebounce;
  Timer? _completedSearchDebounce;

  @override
  void initState() {
    super.initState();
    _pendingSearchController.addListener(() {
      _pendingSearchDebounce?.cancel();
      _pendingSearchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(
            () => _pendingQuery = _pendingSearchController.text
                .trim()
                .toLowerCase(),
          );
        }
      });
    });
    _completedSearchController.addListener(() {
      _completedSearchDebounce?.cancel();
      _completedSearchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(
            () => _completedQuery = _completedSearchController.text
                .trim()
                .toLowerCase(),
          );
        }
      });
    });
    _checkLock();
  }

  @override
  void dispose() {
    _pendingSearchController.dispose();
    _completedSearchController.dispose();
    _pendingSearchDebounce?.cancel();
    _completedSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _checkLock() async {
    final shouldAuth = await WalletLockService.unlockIfNeeded(
      screenKey: 'orders',
      reason: 'Authenticate to view your orders',
    );
    if (!mounted) return;
    if (shouldAuth) {
      setState(() {
        _isLocked = false;
        _checkingLock = false;
      });
      ref
          .read(orderProvider.notifier)
          .loadOrders(); // ignore: unawaited_futures
    } else {
      setState(() {
        _isLocked = true;
        _checkingLock = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderProv = ref.watch(orderProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('My Orders'),
        ),
        body: const Center(child: Text('Sign in to view your orders')),
      );
    }

    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('My Orders'),
        ),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 6),
        ),
      );
    }

    if (_isLocked) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('My Orders'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: context.rw(80),
                height: context.rh(80),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.lock,
                  size: context.ri(40),
                  color: AppTheme.accent,
                ),
              ),
              SizedBox(height: context.rh(16)),
              Text(
                'Orders Locked',
                style: TextStyle(
                  fontSize: context.rsp(20),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(8)),
              Text(
                'Use your fingerprint or screen lock\nto view your orders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              SizedBox(height: context.rh(24)),
              ShadButton(
                onPressed: () async {
                  final provider = ref.read(orderProvider.notifier);
                  final authed = await WalletLockService.authenticate(
                    reason: 'Authenticate to view your orders',
                  );
                  if (authed && mounted) {
                    setState(() => _isLocked = false);
                    provider.loadOrders(); // ignore: unawaited_futures
                  }
                },
                leading: Icon(LucideIcons.fingerprint, size: context.ri(20)),
                child: const Text('Unlock Orders'),
              ),
              SizedBox(height: context.rh(12)),
              ShadButton.ghost(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (orderProv.error != null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('My Orders'),
        ),
        body: Center(
          child: Padding(
            padding: context.rAll(16),
            child: Text(
              'Error: ${orderProv.error}',
              style: const TextStyle(color: AppTheme.destructive),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('My Orders'),
          // General delivery QR lives in the header — one code for every
          // pending item, shown only while something awaits delivery.
          actions: [
            if (_hasPendingDeliveries(_pendingOrders(orderProv.orders)))
              ShadIconButton.ghost(
                icon: Icon(
                  LucideIcons.qrCode,
                  size: 22,
                  color: AppTheme.accent,
                ),
                onPressed: _showGeneralQr,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(
                    sigmaX: AppTheme.glassBlurHeavy,
                    sigmaY: AppTheme.glassBlurHeavy,
                  ),
                  inner: const ColorFilter.matrix(AppTheme.saturateMatrix),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.pureSurface.withValues(alpha: 0.7),
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.whisperBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: TabBar(
                    indicatorColor: AppTheme.accent,
                    labelColor: AppTheme.accent,
                    unselectedLabelColor: AppTheme.mutedSteel,
                    labelStyle: TextStyle(
                      fontSize: context.rsp(13),
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontSize: context.rsp(13),
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      Tab(text: 'Pending (${_pendingCount(orderProv.orders)})'),
                      Tab(
                        text:
                            'Completed (${_completedCount(orderProv.orders)})',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: orderProv.isLoading
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  context.rw(16),
                  MediaQuery.of(context).padding.top +
                      kToolbarHeight +
                      kTextTabBarHeight +
                      context.rh(16),
                  context.rw(16),
                  context.rh(16),
                ),
                child: const ListSkeleton(count: 6),
              )
            : TabBarView(
                children: [
                  _buildOrderTab(
                    orders: _pendingOrders(orderProv.orders),
                    searchController: _pendingSearchController,
                    query: _pendingQuery,
                    emptyTitle: 'No pending orders',
                    emptyDescription: 'Active orders will appear here.',
                  ),
                  _buildOrderTab(
                    orders: _completedOrders(orderProv.orders),
                    searchController: _completedSearchController,
                    query: _completedQuery,
                    emptyTitle: 'No completed orders',
                    emptyDescription:
                        'Delivered and cancelled orders will appear here.',
                  ),
                ],
              ),
      ),
    );
  }

  List<Order> _pendingOrders(List<Order> orders) => orders.where((o) {
    final s = o.status.toLowerCase();
    return s == 'pending' || s == 'processing' || s == 'shipped';
  }).toList();

  List<Order> _completedOrders(List<Order> orders) => orders.where((o) {
    final s = o.status.toLowerCase();
    return s == 'delivered' || s == 'cancelled';
  }).toList();

  int _pendingCount(List<Order> orders) => _pendingOrders(orders).length;
  int _completedCount(List<Order> orders) => _completedOrders(orders).length;

  /// Whether any pending order still has an item awaiting delivery
  /// verification — the general delivery QR is only useful then.
  bool _hasPendingDeliveries(List<Order> orders) => orders.any(
    (o) => o.items.any(
      (i) =>
          i.deliveryCode != null &&
          i.deliveryCode!.isNotEmpty &&
          (i.status == 'pending' || i.status == 'processing'),
    ),
  );

  void _showGeneralQr() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    showShadSheet(
      context: context,
      builder: (_) =>
          ShadSheet(child: _GeneralQrSheet(payload: 'instiy-gqr:${user.id}')),
    );
  }

  List<Order> _searchOrders(List<Order> orders, String query) {
    if (query.isEmpty) return orders;
    return orders.where((o) {
      // Match order ID
      if (o.id.toLowerCase().contains(query)) return true;
      // Match status
      if (o.status.toLowerCase().contains(query)) return true;
      // Match any product title in the order
      return o.items.any(
        (item) => item.productTitle.toLowerCase().contains(query),
      );
    }).toList();
  }

  Widget _buildOrderTab({
    required List<Order> orders,
    required TextEditingController searchController,
    required String query,
    required String emptyTitle,
    required String emptyDescription,
  }) {
    final filtered = _searchOrders(orders, query);
    return Column(
      children: [
        // Search bar
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.rw(16),
            MediaQuery.of(context).padding.top +
                kToolbarHeight +
                kTextTabBarHeight +
                context.rh(12),
            context.rw(16),
            context.rh(8),
          ),
          child: ShadInput(
            controller: searchController,
            placeholder: Text('Search orders by name or ID...'),
            leading: Icon(
              LucideIcons.search,
              size: context.ri(18),
              color: AppTheme.mutedSteel,
            ),
            trailing: searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                    child: Icon(
                      LucideIcons.x,
                      size: context.ri(16),
                      color: AppTheme.mutedSteel,
                    ),
                  )
                : null,
          ),
        ),
        // Order list
        Expanded(
          child: filtered.isEmpty
              ? RefreshIndicator(
                  edgeOffset:
                      MediaQuery.of(context).padding.top +
                      kToolbarHeight +
                      kTextTabBarHeight,
                  onRefresh: () =>
                      ref.read(orderProvider.notifier).loadOrders(),
                  child: ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.12,
                      ),
                      EmptyState(
                        icon: LucideIcons.package,
                        title: emptyTitle,
                        description: query.isNotEmpty
                            ? 'No orders match "$query"'
                            : emptyDescription,
                        actionLabel: query.isEmpty ? 'Start Shopping' : null,
                        onActionPressed: query.isEmpty
                            ? () => Navigator.of(context).pushNamed('/explore')
                            : null,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  edgeOffset:
                      MediaQuery.of(context).padding.top +
                      kToolbarHeight +
                      kTextTabBarHeight,
                  onRefresh: () =>
                      ref.read(orderProvider.notifier).loadOrders(),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      context.rw(16),
                      context.rh(4),
                      context.rw(16),
                      context.rh(16),
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: context.rh(12)),
                    itemBuilder: (context, index) {
                      return _OrderCard(order: filtered[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warningAmber;
      case 'processing':
        return Colors.blue;
      case 'shipped':
        return AppTheme.accent;
      case 'delivered':
        return AppTheme.successMoss;
      case 'cancelled':
        return AppTheme.destructive;
      default:
        return AppTheme.mutedSteel;
    }
  }

  List<OrderItem> get _itemsWithQr => widget.order.items
      .where((i) => i.deliveryCode != null && i.deliveryCode!.isNotEmpty)
      .toList();

  void _showQrModal(OrderItem item) {
    showShadSheet(
      context: context,
      builder: (_) => ShadSheet(child: _QrCodeSheet(item: item)),
    );
  }

  void _showItemPicker(List<OrderItem> items) {
    showShadSheet(
      context: context,
      builder: (_) => ShadSheet(
        title: const Text('Select an item'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...items.map(
              (item) => Padding(
                padding: EdgeInsets.only(bottom: context.rh(8)),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _showQrModal(item);
                  },
                  child: Container(
                    padding: context.rAll(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(context.rr(12)),
                      border: Border.all(color: AppTheme.whisperBorder),
                    ),
                    child: Row(
                      children: [
                        if (item.productThumbnail != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(context.rr(8)),
                            child: SizedBox(
                              width: context.rw(44),
                              height: context.rh(44),
                              child: CachedNetworkImage(
                                imageUrl: item.productThumbnail!,
                                fit: BoxFit.cover,
                                memCacheWidth: 44,
                                placeholder: (_, _) =>
                                    Container(color: AppTheme.warmMist),
                                errorWidget: (_, _, _) =>
                                    Container(color: AppTheme.warmMist),
                              ),
                            ),
                          )
                        else
                          const Icon(
                            LucideIcons.qrCode,
                            color: AppTheme.accent,
                          ),
                        SizedBox(width: context.rw(12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Code: ${item.deliveryCode}',
                                style: TextStyle(fontSize: context.rsp(12)),
                              ),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevronRight, size: context.ri(18)),
                      ],
                    ),
                  ),
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
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).pushNamed('/order-detail', arguments: widget.order.id),
      child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${widget.order.id.toString().substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                Container(
                  padding: context.rPadding(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(
                      widget.order.status,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(context.rr(12)),
                  ),
                  child: Text(
                    widget.order.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: context.rsp(11),
                      fontWeight: FontWeight.w600,
                      color: _statusColor(widget.order.status),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(8)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Total: ',
                            style: TextStyle(
                              color: AppTheme.mutedSteel,
                              fontSize: context.rsp(13),
                            ),
                          ),
                          Text(
                            formatGhs(widget.order.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                        ],
                      ),
                      if (widget.order.deliveryFee > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '(incl. ${formatGhs(widget.order.deliveryFee)} delivery)',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.rw(8)),
                Text(
                  DateFormat('MMM d, yyyy').format(widget.order.createdAt),
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
            if (widget.order.items.isNotEmpty) ...[
              SizedBox(height: context.rh(12)),
              const Divider(height: 1),
              SizedBox(height: context.rh(12)),
              SizedBox(
                height: context.rh(60),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.order.items.length,
                  separatorBuilder: (_, _) => SizedBox(width: context.rw(8)),
                  itemBuilder: (context, index) {
                    final item = widget.order.items[index];
                    return Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(context.rr(8)),
                          child: SizedBox(
                            width: context.rw(50),
                            height: context.rh(50),
                            child: item.productThumbnail != null
                                ? CachedNetworkImage(
                                    imageUrl: item.productThumbnail!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 50,
                                    placeholder: (_, _) =>
                                        Container(color: AppTheme.warmMist),
                                    errorWidget: (_, _, _) =>
                                        Container(color: AppTheme.warmMist),
                                  )
                                : Container(
                                    color: AppTheme.warmMist,
                                    child: Icon(
                                      LucideIcons.shoppingBag,
                                      size: context.ri(20),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(width: context.rw(8)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: context.rw(120),
                              ),
                              child: Text(
                                item.productTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: context.rsp(13),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              'x${item.quantity}',
                              style: TextStyle(
                                fontSize: context.rsp(12),
                                color: AppTheme.mutedSteel,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            // View QR button
            if (_itemsWithQr.isNotEmpty) ...[
              SizedBox(height: context.rh(12)),
              AppButton.outline(
                onPressed: () {
                  if (_itemsWithQr.length == 1) {
                    _showQrModal(_itemsWithQr.first);
                  } else {
                    _showItemPicker(_itemsWithQr);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.qrCode, size: context.ri(18)),
                    SizedBox(width: context.rw(8)),
                    const Text('View QR Code'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrCodeSheet extends StatelessWidget {
  final OrderItem item;

  const _QrCodeSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Container(
          width: context.rw(40),
          height: context.rh(4),
          decoration: BoxDecoration(
            color: AppTheme.whisperBorder,
            borderRadius: BorderRadius.circular(context.rr(2)),
          ),
        ),
        SizedBox(height: context.rh(20)),

        // Product title
        Text(
          item.productTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: context.rsp(16),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(20)),

        // QR Code
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.1),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                data: item.deliveryCode!,
                version: QrVersions.auto,
                size: context.rw(200),
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
                embeddedImage:
                    item.productThumbnail != null &&
                        item.productThumbnail!.isNotEmpty
                    ? CachedNetworkImageProvider(item.productThumbnail!)
                    : const AssetImage('assets/logo_highres.png')
                          as ImageProvider,
                embeddedImageStyle: const QrEmbeddedImageStyle(
                  size: Size(40, 40),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      item.productThumbnail != null &&
                          item.productThumbnail!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.productThumbnail!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Image.asset('assets/logo_highres.png'),
                          errorWidget: (_, _, _) =>
                              Image.asset('assets/logo_highres.png'),
                        )
                      : Image.asset(
                          'assets/logo_highres.png',
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.rh(20)),

        // Delivery code with copy button
        Container(
          padding: context.rPadding(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.warmMist,
            borderRadius: BorderRadius.circular(context.rr(12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Code',
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        fontWeight: FontWeight.w500,
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                    SizedBox(height: context.rh(2)),
                    Text(
                      item.deliveryCode!,
                      style: TextStyle(
                        fontSize: context.rsp(20),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: context.rw(12)),
              ShadIconButton.ghost(
                icon: Icon(LucideIcons.copy, size: context.ri(22)),
                foregroundColor: AppTheme.accent,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: item.deliveryCode!),
                  );
                  if (context.mounted) {
                    ShadToaster.of(context).show(
                      ShadToast(
                        title: Row(
                          children: [
                            Icon(
                              LucideIcons.check,
                              color: AppTheme.successMoss,
                              size: context.ri(18),
                            ),
                            SizedBox(width: context.rw(8)),
                            const Text('Code copied to clipboard'),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        SizedBox(height: context.rh(12)),

        // Instruction text
        Text(
          'Show this QR code to the seller when collecting your item.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rsp(13),
            color: AppTheme.mutedSteel,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// One QR for every pending delivery. Encodes only the buyer id — the seller's
/// scanner resolves their own items for this buyer server-side, so no other
/// seller's delivery codes are ever exposed.
class _GeneralQrSheet extends StatelessWidget {
  final String payload;

  const _GeneralQrSheet({required this.payload});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Container(
          width: context.rw(40),
          height: context.rh(4),
          decoration: BoxDecoration(
            color: AppTheme.whisperBorder,
            borderRadius: BorderRadius.circular(context.rr(2)),
          ),
        ),
        SizedBox(height: context.rh(20)),

        // Title
        Text(
          'All Pending Deliveries',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rsp(16),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(20)),

        // QR Code
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.1),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: context.rw(200),
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/logo_highres.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.rh(20)),

        // Instruction text
        Text(
          'Show this code to any seller — they can only see and verify the items you bought from them.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rsp(13),
            color: AppTheme.mutedSteel,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
