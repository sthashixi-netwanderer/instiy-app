import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/seller_service.dart';
import '../../services/wallet_lock_service.dart';
import '../../models/order_model.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import 'scanner_screen.dart';
import '../../widgets/skeleton.dart';

class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> {
  bool _isLocked = true;
  bool _checkingLock = true;
  String _filter = 'all';

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
      unawaited(_loadOrders());
    } else {
      setState(() {
        _isLocked = true;
        _checkingLock = false;
      });
    }
  }

  /// Loads orders into sellerProvider, which keeps them fresh via its own
  /// realtime subscription (no screen-level channel needed).
  Future<void> _loadOrders() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    await ref.read(sellerProvider).ensureInitialized(user.id);
  }

  /// Force-fetches the latest orders (used after user actions).
  Future<void> _refreshOrders() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    await ref.read(sellerProvider).loadSellerOrders(user.id);
  }

  List<Order> _filterOrders(List<Order> orders) {
    if (_filter == 'all') return orders;
    return orders.where((o) {
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedSteel,
                  ),
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
        if (!mounted) return;
        // Auto-close pops the scanner with the scanned code as the route
        // result, so verification (and its confirmation toast) starts
        // immediately after the read instead of waiting for a manual back.
        final scannedCode = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => const ScannerScreen(autoClose: true),
          ),
        );
        if (scannedCode == null || scannedCode.isEmpty) return;
        await _verifyAndComplete(item, scannedCode);
      } else {
        final code = await _showCodeInputDialog(item);
        if (code == null || code.isEmpty) return;
        await _verifyAndComplete(item, code);
      }
      return;
    }

    final parentOrder = ref
        .read(sellerProvider)
        .sellerOrders
        .firstWhere((o) => o.id == item.orderId);
    final deliveryFee = parentOrder.deliveryMode == 'delivery'
        ? parentOrder.deliveryFee
        : 0.0;
    final totalCredit = (item.price * item.quantity) + deliveryFee;

    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Complete Order Item'),
      description: Text(
        'Mark "${item.productTitle}" as delivered?\n\n'
        'You will be credited ${formatGhs(totalCredit)} to your wallet.'
        '${deliveryFee > 0 ? ' (includes ${formatGhs(deliveryFee)} delivery fee)' : ''}',
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
        ShadToast(
          backgroundColor: AppTheme.successMoss,
          title: Text('${item.productTitle} marked as delivered'),
        ),
      );
      unawaited(_refreshOrders());
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Error: $e'),
        ),
      );
    }
  }

  Future<String?> _showCodeInputDialog(OrderItem item) async {
    final codeController = TextEditingController();
    return AppTheme.showGlassDialog<String>(
      context: context,
      title: const Text('Enter Delivery Code'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
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
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
              ),
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
        AnimatedBuilder(
          animation: codeController,
          builder: (context, _) {
            final canVerify = codeController.text.trim().isNotEmpty;
            return ShadButton(
              backgroundColor: AppTheme.successMoss,
              foregroundColor: Colors.white,
              enabled: canVerify,
              onPressed: canVerify
                  ? () => Navigator.of(
                      context,
                    ).pop(codeController.text.trim().toUpperCase())
                  : null,
              child: const Text('Verify'),
            );
          },
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
            title: Text(
              'Verified! ${formatGhs((result['amount'] as num?) ?? 0)} released to wallet.',
            ),
          ),
        );
        unawaited(_refreshOrders());
      } else {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text(result['error'] as String? ?? 'Verification failed'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Error: $e'),
        ),
      );
    }
  }

  Future<void> _cancelItem(OrderItem item) async {
    final reasonController = TextEditingController();
    final result = await AppTheme.showGlassDialog<Map<String, dynamic>>(
      context: context,
      title: const Text('Cancel Order Item'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cancel "${item.productTitle}"? The buyer will be refunded ${formatGhs(item.price * item.quantity)}.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Reason for cancellation *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 8),
            ShadInput(
              controller: reasonController,
              placeholder: const Text(
                'e.g. Out of stock, item damaged, buyer request...',
              ),
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
        AnimatedBuilder(
          animation: reasonController,
          builder: (context, _) {
            final reasonValid = reasonController.text.trim().isNotEmpty;
            return ShadButton.destructive(
              enabled: reasonValid,
              onPressed: reasonValid
                  ? () {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) {
                        ShadToaster.of(context).show(
                          const ShadToast(
                            backgroundColor: AppTheme.destructive,
                            title: Text('Please provide a reason'),
                          ),
                        );
                        return;
                      }
                      Navigator.of(
                        context,
                      ).pop({'confirmed': true, 'reason': reason});
                    }
                  : null,
              child: const Text('Cancel & Refund'),
            );
          },
        ),
      ],
    );

    if (result == null || result['confirmed'] != true) return;

    try {
      await SellerService.cancelOrderItem(
        item.id,
        reason: result['reason'] as String,
      );
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.warningAmber,
          title: Text('${item.productTitle} cancelled. Buyer refunded.'),
        ),
      );
      unawaited(_refreshOrders());
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Error: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final orders = sellerProv.sellerOrders;
    final isLoading = sellerProv.isLoading && orders.isEmpty;
    final error = orders.isEmpty ? sellerProv.error : null;
    final filteredOrders = _filterOrders(orders);

    // Total the seller's wallet will receive once every pending item is
    // completed — mirrors the server payout formula (price * quantity,
    // plus the delivery fee for each item in delivery-mode orders).
    var pendingCount = 0;
    var pendingTotal = 0.0;
    for (final order in orders) {
      final deliveryFee = order.deliveryMode == 'delivery'
          ? order.deliveryFee
          : 0.0;
      for (final item in order.items) {
        if (item.status == 'pending') {
          pendingCount++;
          pendingTotal += item.price * item.quantity + deliveryFee;
        }
      }
    }
    final showPendingBalance = orders.isNotEmpty;
    final pendingCardExtra = showPendingBalance ? context.rh(56) + 8 : 0.0;

    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Orders'),
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
          title: const Text('Orders'),
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
                    unawaited(_loadOrders());
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
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Orders'),
      ),
      body: Stack(
        children: [
          // Content extends behind the filter chips
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset:
                  MediaQuery.paddingOf(context).top +
                  kToolbarHeight +
                  56 +
                  pendingCardExtra,
              onRefresh: () async {
                final user = ref.read(authProvider).user;
                if (user != null) {
                  await ref.read(sellerProvider).loadSellerOrders(user.id);
                }
              },
              child: isLoading
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.paddingOf(context).top + kToolbarHeight + 64,
                        16,
                        16,
                      ),
                      child: const ListSkeleton(count: 6),
                    )
                  : error != null
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.6,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.circleAlert,
                              size: context.ri(48),
                              color: AppTheme.destructive,
                            ),
                            SizedBox(height: context.rh(12)),
                            Text(
                              error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.destructive,
                              ),
                            ),
                            SizedBox(height: context.rh(16)),
                            ShadButton(
                              onPressed: () async {
                                final user = ref.read(authProvider).user;
                                if (user != null) {
                                  await ref
                                      .read(sellerProvider)
                                      .ensureInitialized(user.id, force: true);
                                }
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filteredOrders.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.6,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.shoppingBag,
                              size: context.ri(64),
                              color: Colors.grey[300],
                            ),
                            SizedBox(height: context.rh(16)),
                            Text(
                              _filter == 'all'
                                  ? 'No orders yet'
                                  : 'No $_filter orders',
                              style: TextStyle(
                                fontSize: context.rsp(18),
                                fontWeight: FontWeight.w600,
                                color: AppTheme.charcoalInk,
                              ),
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
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.paddingOf(context).top +
                            kToolbarHeight +
                            64 +
                            pendingCardExtra,
                        16,
                        16,
                      ),
                      itemCount: filteredOrders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _SellerOrderCard(
                        order: filteredOrders[index],
                        statusColor: _statusColor,
                        onCompleteItem: _completeItem,
                        onCancelItem: _cancelItem,
                      ),
                    ),
            ),
          ),
          // Floating pending balance + filter chips (transparent to content behind)
          Positioned(
            top:
                MediaQuery.paddingOf(context).top +
                kToolbarHeight +
                context.rh(12),
            left: context.rw(16),
            right: context.rw(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showPendingBalance) ...[
                  _PendingBalanceCard(
                    total: pendingTotal,
                    pendingCount: pendingCount,
                  ),
                  SizedBox(height: context.rh(8)),
                ],
                Material(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-height summary showing what the seller's wallet will receive once
/// every pending order item is completed. Height must stay in sync with the
/// [pendingCardExtra] offset used for the list top padding.
class _PendingBalanceCard extends StatelessWidget {
  final double total;
  final int pendingCount;

  const _PendingBalanceCard({required this.total, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.rh(56),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.rw(14)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: context.rAll(8),
              decoration: BoxDecoration(
                color: AppTheme.successMoss.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.wallet,
                size: context.ri(16),
                color: AppTheme.successMoss,
              ),
            ),
            SizedBox(width: context.rw(10)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pending Balance',
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(1)),
                  Text(
                    pendingCount == 0
                        ? 'No pending items to complete'
                        : 'From $pendingCount pending ${pendingCount == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      fontSize: context.rsp(11),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: context.rw(10)),
            Text(
              formatGhs(total),
              style: TextStyle(
                fontSize: context.rsp(16),
                fontWeight: FontWeight.bold,
                color: AppTheme.successMoss,
              ),
            ),
          ],
        ),
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
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(16),
          vertical: context.rh(8),
        ),
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
                style: TextStyle(
                  fontSize: context.rsp(12),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(4)),
          Text(
            'Payment: ${order.paymentStatus.toUpperCase()}',
            style: TextStyle(
              fontSize: context.rsp(12),
              fontWeight: FontWeight.w600,
              color: order.paymentStatus == 'paid'
                  ? AppTheme.successMoss
                  : AppTheme.warningAmber,
            ),
          ),
          SizedBox(height: context.rh(12)),
          const Divider(height: 1),
          SizedBox(height: context.rh(12)),
          ...order.items.map(
            (item) => Padding(
              padding: EdgeInsets.only(bottom: context.rh(12)),
              child: _SellerItemRow(
                item: item,
                statusColor: statusColor,
                onComplete: () => onCompleteItem(item),
                onCancel: () => onCancelItem(item),
              ),
            ),
          ),
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
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Text(
                    '${formatGhs(item.price)} x${item.quantity}',
                    style: TextStyle(
                      color: AppTheme.mutedSteel,
                      fontSize: context.rsp(13),
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(3),
                        ),
                        decoration: BoxDecoration(
                          color: statusColor(
                            item.status ?? 'pending',
                          ).withValues(alpha: 0.1),
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
                        Icon(
                          LucideIcons.lock,
                          size: context.ri(12),
                          color: AppTheme.mutedSteel,
                        ),
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
