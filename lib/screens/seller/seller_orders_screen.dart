import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/seller_service.dart';
import '../../services/supabase_service.dart';
import '../../services/wallet_lock_service.dart';
import '../../models/order_model.dart';
import '../../utils/responsive.dart';
import 'scanner_screen.dart';
import '../../widgets/skeleton.dart';

class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  bool _isLocked = true;
  bool _checkingLock = true;
  String? _error;
  String _filter = 'all';
  RealtimeChannel? _orderItemsChannel;

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final shouldAuth = await WalletLockService.unlockIfNeeded(
      reason: 'Authenticate to view seller orders',
    );
    if (!mounted) return;
    if (shouldAuth) {
      setState(() {
        _isLocked = false;
        _checkingLock = false;
      });
      _loadOrders();
      _subscribeToRealtime();
    } else {
      setState(() {
        _isLocked = true;
        _checkingLock = false;
      });
    }
  }

  void _subscribeToRealtime() {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    _orderItemsChannel = SupabaseService.client
        .channel('seller-orders-screen:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _loadOrders(),
        );
    _orderItemsChannel!.subscribe();
  }

  @override
  void dispose() {
    if (_orderItemsChannel != null) {
      SupabaseService.client.removeChannel(_orderItemsChannel!);
    }
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orders = await SellerService.getSellerOrders(user.id);
      if (mounted) setState(() => _orders = orders);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Order> get _filteredOrders {
    if (_filter == 'all') return _orders;
    return _orders.where((o) {
      if (_filter == 'pending') {
        return o.items.any((i) => i.status == 'pending');
      }
      if (_filter == 'delivered') {
        return o.items.any((i) => i.status == 'delivered');
      }
      return true;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warningAmber;
      case 'delivered':
        return AppTheme.successMoss;
      case 'cancelled':
        return AppTheme.destructive;
      default:
        return AppTheme.mutedSteel;
    }
  }

  Future<void> _completeItem(OrderItem item) async {
    final hasCode = item.deliveryCode != null && item.deliveryCode!.isNotEmpty;

    if (hasCode) {
      final choice = await showShadSheet<String>(
        context: context,
        builder: (_) => ShadSheet(
          title: const Text('Verify Delivery'),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ask the buyer for their delivery code for "${item.productTitle}".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppTheme.mutedSteel),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _OptionButton(
                        icon: LucideIcons.keyboard,
                        label: 'Enter Code',
                        onTap: () => Navigator.of(context).pop('manual'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _OptionButton(
                        icon: LucideIcons.scanLine,
                        label: 'Scan QR',
                        onTap: () => Navigator.of(context).pop('scan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (choice == null) return;

      if (choice == 'scan') {
        String? scannedCode;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ScannerScreen(
              onDetect: (code) {
                scannedCode = code;
              },
            ),
          ),
        );
        if (scannedCode == null || scannedCode!.isEmpty) return;
        await _verifyAndComplete(item, scannedCode!);
      } else {
        final code = await _showCodeInputDialog(item);
        if (code == null || code.isEmpty) return;
        await _verifyAndComplete(item, code);
      }
      return;
    }

    final parentOrder = _orders.firstWhere((o) => o.id == item.orderId);
    final deliveryFee = parentOrder.deliveryMode == 'delivery' ? parentOrder.deliveryFee : 0.0;
    final totalCredit = (item.price * item.quantity) + deliveryFee;

    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Complete Order Item'),
      description: Text(
        'Mark "${item.productTitle}" as delivered?\n\n'
        'You will be credited GH\u00a2 ${totalCredit.toStringAsFixed(2)} to your wallet.'
        '${deliveryFee > 0 ? ' (includes GH\u00a2 ${deliveryFee.toStringAsFixed(2)} delivery fee)' : ''}',
      ),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(false),
      child: const Text('Cancel'),
    ),
    ShadButton(
      backgroundColor: AppTheme.successMoss,
      foregroundColor: Colors.white,
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text('Confirm Delivery'),
    ),
  ],
);

    if (confirmed != true) return;

    try {
      await SellerService.completeOrderItem(item.id);
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(backgroundColor: AppTheme.successMoss, title: Text('${item.productTitle} marked as delivered')),
      );
      _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(backgroundColor: AppTheme.destructive, title: Text('Error: $e')),
      );
    }
  }

  Future<String?> _showCodeInputDialog(OrderItem item) async {
    final codeController = TextEditingController();
return AppTheme.showGlassDialog<String>(
  context: context,
  title: const Text('Enter Delivery Code'),
  child: SingleChildScrollView(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter the code the buyer provided for "${item.productTitle}".',
          style: const TextStyle(fontSize: 14, color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 16),
        ShadInput(
          controller: codeController,
          placeholder: const Text('e.g. X7K9M2'),
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  ),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    ),
    ShadButton(
      backgroundColor: AppTheme.successMoss,
      foregroundColor: Colors.white,
      onPressed: () => Navigator.of(context).pop(codeController.text.trim().toUpperCase()),
      child: const Text('Verify'),
    ),
  ],
);
  }

  Future<void> _verifyAndComplete(OrderItem item, String code) async {
    try {
      final result = await SellerService.verifyDelivery(item.id, code);
      if (!mounted) return;
      if (result['success'] == true) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.successMoss,
            title: Text('Verified! GH\u00a2 ${(result['amount'] as num?)?.toStringAsFixed(2) ?? ''} released to wallet.'),
          ),
        );
        _loadOrders();
      } else {
        ShadToaster.of(context).show(
          ShadToast(backgroundColor: AppTheme.destructive, title: Text(result['error'] as String? ?? 'Verification failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(backgroundColor: AppTheme.destructive, title: Text('Error: $e')),
      );
    }
  }

  Future<void> _cancelItem(OrderItem item) async {
    final reasonController = TextEditingController();
final result = await AppTheme.showGlassDialog<Map<String, dynamic>>(
  context: context,
  title: const Text('Cancel Order Item'),
  child: SingleChildScrollView(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cancel "${item.productTitle}"? The buyer will be refunded GH\u00a2 ${(item.price * item.quantity).toStringAsFixed(2)}.',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        const Text(
          'Reason for cancellation *',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: reasonController,
          placeholder: const Text('e.g. Out of stock, item damaged, buyer request...'),
          maxLines: 3,
        ),
      ],
    ),
  ),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Go Back'),
    ),
    ShadButton.destructive(
      onPressed: () {
        final reason = reasonController.text.trim();
        if (reason.isEmpty) {
          ShadToaster.of(context).show(
            const ShadToast(backgroundColor: AppTheme.destructive, title: Text('Please provide a reason')),
          );
          return;
        }
        Navigator.of(context).pop({'confirmed': true, 'reason': reason});
      },
      child: const Text('Cancel & Refund'),
    ),
  ],
);

    if (result == null || result['confirmed'] != true) return;

    try {
      await SellerService.cancelOrderItem(item.id, reason: result['reason'] as String);
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(backgroundColor: AppTheme.warningAmber, title: Text('${item.productTitle} cancelled. Buyer refunded.')),
      );
      _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(backgroundColor: AppTheme.destructive, title: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Orders')),
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
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Orders')),
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
                'Use your fingerprint or screen lock\nto view seller orders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              SizedBox(height: context.rh(24)),
              ShadButton(
                onPressed: () async {
                  final authed = await WalletLockService.authenticate(
                    reason: 'Authenticate to view seller orders',
                  );
                  if (authed && mounted) {
                    setState(() => _isLocked = false);
                    _loadOrders();
                    _subscribeToRealtime();
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

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, 
        title: const Text('Orders'),
      ),
      body: Stack(
        children: [
          // Content extends behind the filter chips
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + 56,
              onRefresh: _loadOrders,
              child: _isLoading
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 64, 16, 16),
                      child: const ListSkeleton(count: 6),
                    )
                  : _error != null
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.6,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.circleAlert, size: context.ri(48), color: AppTheme.destructive),
                                SizedBox(height: context.rh(12)),
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.destructive)),
                                SizedBox(height: context.rh(16)),
                                ShadButton(onPressed: _loadOrders, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _filteredOrders.isEmpty
                          ? SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: MediaQuery.of(context).size.height * 0.6,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.shoppingBag, size: context.ri(64), color: Colors.grey[300]),
                                    SizedBox(height: context.rh(16)),
                                    Text(
                                      _filter == 'all' ? 'No orders yet' : 'No $_filter orders',
                                      style: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                                    ),
                                    SizedBox(height: context.rh(8)),
                                    const Text(
                                      'Orders for your products will appear here.',
                                      style: TextStyle(color: AppTheme.mutedSteel),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 64, 16, 16),
                              itemCount: _filteredOrders.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) => _SellerOrderCard(
                                order: _filteredOrders[index],
                                statusColor: _statusColor,
                                onCompleteItem: _completeItem,
                                onCancelItem: _cancelItem,
                              ),
                            ),
            ),
          ),
          // Floating filter chips (transparent to content behind)
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(12),
            left: context.rw(16),
            right: context.rw(16),
            child: Material(
              color: Colors.transparent,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Pending',
                    selected: _filter == 'pending',
                    onTap: () => setState(() => _filter = 'pending'),
                  ),
                  SizedBox(width: context.rw(8)),
                  _FilterChip(
                    label: 'Delivered',
                    selected: _filter == 'delivered',
                    onTap: () => setState(() => _filter = 'delivered'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(8)),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(20)),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.whisperBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: context.rsp(13),
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.charcoalInk,
          ),
        ),
      ),
    );
  }
}

class _SellerOrderCard extends StatelessWidget {
  final Order order;
  final Color Function(String) statusColor;
  final void Function(OrderItem) onCompleteItem;
  final void Function(OrderItem) onCancelItem;

  const _SellerOrderCard({
    required this.order,
    required this.statusColor,
    required this.onCompleteItem,
    required this.onCancelItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Expanded(
                child: Text(
                  'Order #${order.id.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(15),
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(order.createdAt),
                style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
              ),
            ],
          ),
          SizedBox(height: context.rh(4)),
          Text(
            'Payment: ${order.paymentStatus.toUpperCase()}',
            style: TextStyle(
              fontSize: context.rsp(12),
              fontWeight: FontWeight.w600,
              color: order.paymentStatus == 'paid' ? AppTheme.successMoss : AppTheme.warningAmber,
            ),
          ),
          SizedBox(height: context.rh(12)),
          const Divider(height: 1),
          SizedBox(height: context.rh(12)),
          ...order.items.map((item) => Padding(
            padding: EdgeInsets.only(bottom: context.rh(12)),
            child: _SellerItemRow(
              item: item,
              statusColor: statusColor,
              onComplete: () => onCompleteItem(item),
              onCancel: () => onCancelItem(item),
            ),
          )),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(20)),
        decoration: BoxDecoration(
          color: AppTheme.canvasWhite,
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Column(
          children: [
            Container(
              padding: context.rAll(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.accent, size: context.ri(28)),
            ),
            SizedBox(height: context.rh(10)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(14),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerItemRow extends StatelessWidget {
  final OrderItem item;
  final Color Function(String) statusColor;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _SellerItemRow({
    required this.item,
    required this.statusColor,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = item.status == 'pending';

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(context.rr(8)),
              child: SizedBox(
                width: context.rw(48),
                height: context.rh(48),
                child: item.productThumbnail != null
                    ? CachedNetworkImage(
                        memCacheWidth: 40,
                        imageUrl: item.productThumbnail!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppTheme.warmMist),
                        errorWidget: (_, _, _) => Container(color: AppTheme.warmMist),
                      )
                    : Container(
                        color: AppTheme.warmMist,
                        child: Icon(LucideIcons.shoppingBag, size: context.ri(20), color: AppTheme.mutedSteel),
                      ),
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.rsp(14)),
                  ),
                  SizedBox(height: context.rh(2)),
                  Text(
                    'GH\u00a2 ${item.price.toStringAsFixed(2)} x${item.quantity}',
                    style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(13)),
                  ),
                  SizedBox(height: context.rh(2)),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(3)),
                        decoration: BoxDecoration(
                          color: statusColor(item.status ?? 'pending').withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Text(
                          (item.status ?? 'pending').toUpperCase(),
                          style: TextStyle(
                            fontSize: context.rsp(10),
                            fontWeight: FontWeight.w600,
                            color: statusColor(item.status ?? 'pending'),
                          ),
                        ),
                      ),
                      if (item.deliveryCode != null) ...[
                        SizedBox(width: context.rw(6)),
                        Icon(LucideIcons.lock, size: context.ri(12), color: AppTheme.mutedSteel),
                        SizedBox(width: context.rw(2)),
                        Text(
                          'Code required',
                          style: TextStyle(
                            fontSize: context.rsp(10),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isPending) ...[
          SizedBox(height: context.rh(10)),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: onCancel,
                  leading: Icon(LucideIcons.x, size: context.ri(16)),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(width: context.rw(10)),
              Expanded(
                child: ShadButton(
                  backgroundColor: AppTheme.successMoss,
                  foregroundColor: Colors.white,
                  onPressed: onComplete,
                  leading: Icon(LucideIcons.check, size: context.ri(16)),
                  child: const Text('Complete'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
