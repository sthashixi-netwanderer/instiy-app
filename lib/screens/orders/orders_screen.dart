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

  @override
  void initState() {
    super.initState();
    _checkLock();
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
      ref.read(orderProvider.notifier).loadOrders(); // ignore: unawaited_futures
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
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('My Orders')),
        body: const Center(child: Text('Sign in to view your orders')),
      );
    }

    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('My Orders')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 6),
        ),
      );
    }

    if (_isLocked) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('My Orders')),
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
                child: Icon(LucideIcons.lock, size: context.ri(40), color: AppTheme.accent),
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
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('My Orders')),
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

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('My Orders')),
      body: orderProv.isLoading
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                context.rw(16),
                MediaQuery.of(context).padding.top + kToolbarHeight + context.rh(16),
                context.rw(16),
                context.rh(16),
              ),
              child: const ListSkeleton(count: 6),
            )
          : orderProv.orders.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight,
                  onRefresh: () => ref.read(orderProvider.notifier).loadOrders(),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      context.rw(16),
                      MediaQuery.of(context).padding.top + kToolbarHeight + context.rh(16),
                      context.rw(16),
                      context.rh(16),
                    ),
                    itemCount: orderProv.orders.length,
                    separatorBuilder: (_, _) => SizedBox(height: context.rh(12)),
                    itemBuilder: (context, index) {
                      return _OrderCard(order: orderProv.orders[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: LucideIcons.package,
      title: 'No orders yet',
      description: 'Orders will appear here after checkout.',
      actionLabel: 'Start Shopping',
      onActionPressed: () => Navigator.of(context).pushNamed('/explore'),
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
      builder: (_) => ShadSheet(
        child: _QrCodeSheet(item: item),
      ),
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
            ...items.map((item) => Padding(
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
                            const Icon(LucideIcons.qrCode, color: AppTheme.accent),
                          SizedBox(width: context.rw(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productTitle,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text('Code: ${item.deliveryCode}',
                                    style: TextStyle(fontSize: context.rsp(12))),
                              ],
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: context.ri(18)),
                        ],
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(
        '/order-detail',
        arguments: widget.order.id,
      ),
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
                  padding:
                      context.rPadding(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(widget.order.status)
                        .withValues(alpha: 0.1),
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
                          Text('Total: ',
                              style: TextStyle(
                                  color: AppTheme.mutedSteel,
                                  fontSize: context.rsp(13))),
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
                      fontSize: context.rsp(12), color: AppTheme.mutedSteel),
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
                                    child: Icon(LucideIcons.shoppingBag, size: context.ri(20), color: AppTheme.mutedSteel),
                                  ),
                          ),
                        ),
                        SizedBox(width: context.rw(8)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: context.rw(120)),
                              child: Text(item.productTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: context.rsp(13), fontWeight: FontWeight.w500)),
                            ),
                            Text('x${item.quantity}',
                                style: TextStyle(
                                    fontSize: context.rsp(12),
                                    color: AppTheme.mutedSteel)),
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
                embeddedImage: item.productThumbnail != null && item.productThumbnail!.isNotEmpty
                    ? CachedNetworkImageProvider(item.productThumbnail!)
                    : const AssetImage('assets/logo_highres.png') as ImageProvider,
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
                  child: item.productThumbnail != null && item.productThumbnail!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.productThumbnail!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Image.asset('assets/logo_highres.png'),
                          errorWidget: (_, _, _) => Image.asset('assets/logo_highres.png'),
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
                      ClipboardData(text: item.deliveryCode!));
                  if (context.mounted) {
                    ShadToaster.of(context).show(
                      ShadToast(
                        title: Row(
                          children: [
                            Icon(LucideIcons.check,
                                color: AppTheme.successMoss, size: context.ri(18)),
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
