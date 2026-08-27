import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/order_model.dart';
import '../../services/seller_service.dart';
import '../../utils/responsive.dart';
import 'scanner_screen.dart';
import 'seller_orders_screen.dart';
import 'package:instiy/utils/formatters.dart';

class SellerVerifyScreen extends ConsumerStatefulWidget {
  const SellerVerifyScreen({super.key});

  @override
  ConsumerState<SellerVerifyScreen> createState() => _SellerVerifyScreenState();
}

class _SellerVerifyScreenState extends ConsumerState<SellerVerifyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref.read(sellerProvider).loadSellerOrders(user.id);
      }
    });
  }

  Future<void> _verifyCode(OrderItem item, String code) async {
    if (code.trim().isEmpty) return;

    final prov = ref.read(sellerProvider);
    final result = await prov.verifyDelivery(item.id, code.trim());

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
      final user = ref.read(authProvider).user;
      if (user != null) {
        prov.loadSellerOrders(user.id); // ignore: unawaited_futures
      }
    } else {
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text(result['error'] as String? ?? 'Verification failed'),
        ),
      );
    }
  }

  void _showManualEntry(OrderItem item) {
    final codeController = TextEditingController();
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Enter Delivery Code'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ShadInput(
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
              enabled: canVerify,
              onPressed: canVerify
                  ? () {
                      Navigator.of(context).pop();
                      _verifyCode(
                        item,
                        codeController.text.trim().toUpperCase(),
                      );
                    }
                  : null,
              child: const Text('Verify'),
            );
          },
        ),
      ],
    );
  }

  Future<void> _scanCode(OrderItem item) async {
    // Auto-close pops the scanner with the scanned value as the route
    // result, so verification (and its success/failure toast) runs right
    // after the read instead of leaving the camera open with no feedback.
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen(autoClose: true)),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _verifyCode(item, code);
  }

  /// Universal delivery QR scanner: one scanner works with BOTH general buyer QR codes
  /// (`instiy-gqr:<buyerId>`) AND specific ordered products (`item.deliveryCode`,
  /// `instiy-code:<codeText>`, `instiy-item:<codeText>`, or raw delivery codes).
  Future<void> _scanUniversalQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          autoClose: true,
          title: 'Scan Delivery QR',
          subtitle: 'Point camera at buyer QR or product delivery code',
        ),
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleScannedCode(code.trim());
  }

  Future<void> _handleScannedCode(String raw) async {
    const gqrPrefix = 'instiy-gqr:';
    if (raw.startsWith(gqrPrefix)) {
      final buyerId = raw.substring(gqrPrefix.length).trim();
      await _openBuyerItems(buyerId);
      return;
    }

    // Clean any prefixes that might be part of an item QR
    String cleanCode = raw;
    if (cleanCode.toLowerCase().startsWith('instiy-code:')) {
      cleanCode = cleanCode.substring('instiy-code:'.length).trim();
    } else if (cleanCode.toLowerCase().startsWith('instiy-item:')) {
      cleanCode = cleanCode.substring('instiy-item:'.length).trim();
    } else if (cleanCode.toLowerCase().startsWith('code:')) {
      cleanCode = cleanCode.substring('code:'.length).trim();
    }

    final sellerProv = ref.read(sellerProvider);
    final allItems = sellerProv.sellerOrders.expand((o) => o.items).toList();
    OrderItem? matchedItem = allItems.cast<OrderItem?>().firstWhere(
      (item) =>
          item != null &&
          (item.deliveryCode?.toUpperCase() == cleanCode.toUpperCase() ||
              item.id.toLowerCase() == cleanCode.toLowerCase()),
      orElse: () => null,
    );

    if (matchedItem != null) {
      if (matchedItem.status == 'delivered') {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.warningAmber,
            title: Text('Already Delivered: "${matchedItem.productTitle}"'),
            description: const Text(
              'This item was already verified and funds released to your wallet.',
            ),
          ),
        );
        return;
      }
      if (matchedItem.status == 'cancelled') {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Order Item Cancelled: "${matchedItem.productTitle}"'),
          ),
        );
        return;
      }

      await _verifyCode(matchedItem, cleanCode);
      return;
    }

    // Fallback: verify server-side via verifyDeliveryByCode RPC
    final result = await sellerProv.verifyDeliveryByCode(cleanCode);
    if (!mounted) return;

    if (result['success'] == true) {
      final amount = (result['amount'] as num?) ?? 0;
      final productTitle = result['product_title'] as String?;
      final titleText = productTitle != null && productTitle.isNotEmpty
          ? 'Verified "$productTitle"! ${formatGhs(amount.toDouble())} released to wallet.'
          : 'Verified! ${formatGhs(amount.toDouble())} released to wallet.';

      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.successMoss,
          title: Text(titleText),
        ),
      );
      final user = ref.read(authProvider).user;
      if (user != null) {
        sellerProv.loadSellerOrders(user.id); // ignore: unawaited_futures
      }
    } else {
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text(
            result['error'] as String? ??
                'Invalid delivery code or item does not belong to your store',
          ),
        ),
      );
    }
  }

  Future<void> _openBuyerItems(String buyerId) async {
    try {
      final result = await SellerService.getBuyerPendingItems(buyerId);
      if (!mounted) return;
      if (result['success'] != true) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text(result['error'] as String? ?? 'Lookup failed'),
          ),
        );
        return;
      }
      final items = (result['items'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      if (items.isEmpty) {
        ShadToaster.of(context).show(
          const ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('This buyer has no pending items from your store'),
          ),
        );
        return;
      }
      unawaited(
        showShadSheet(
          context: context,
          builder: (_) => ShadSheet(
            title: const Text('Deliver Items'),
            child: _BuyerItemsSheet(
              buyerId: buyerId,
              buyerName: result['buyer_name'] as String?,
              items: items,
              onVerified: (result) {
                if (result['success'] == true) {
                  final verified = result['verified'] as num? ?? 0;
                  final amount = (result['amount'] as num?) ?? 0;
                  ShadToaster.of(context).show(
                    ShadToast(
                      backgroundColor: AppTheme.successMoss,
                      title: Text(
                        '$verified item${verified == 1 ? '' : 's'} delivered — '
                        '${formatGhs(amount.toDouble())} released to wallet.',
                      ),
                    ),
                  );
                } else {
                  ShadToaster.of(context).show(
                    ShadToast(
                      backgroundColor: AppTheme.destructive,
                      title: Text(
                        result['error'] as String? ?? 'Verification failed',
                      ),
                    ),
                  );
                }
                final user = ref.read(authProvider).user;
                if (user != null) {
                  ref
                      .read(sellerProvider)
                      .loadSellerOrders(user.id); // ignore: unawaited_futures
                }
              },
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Could not look up this buyer'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Verify Deliveries'),
        ),
        body: const Center(child: Text('Sign in as a seller')),
      );
    }

    final allItems = sellerProv.sellerOrders.expand((o) => o.items).toList();
    final pendingItems = allItems
        .where((i) => i.deliveryCode != null && i.status == 'pending')
        .toList();
    final processingItems = allItems
        .where((i) => i.deliveryCode != null && i.status == 'processing')
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Verify Deliveries'),
        // Universal delivery QR scanner: scans both general buyer QR codes and specific item delivery codes
        actions: [
          if (pendingItems.isNotEmpty || processingItems.isNotEmpty)
            ShadIconButton.ghost(
              icon: const Icon(
                LucideIcons.scanLine,
                size: 22,
                color: AppTheme.accent,
              ),
              onPressed: _scanUniversalQr,
            ),
        ],
      ),
      body: sellerProv.isLoading
          ? const Center(child: CircularProgressIndicator())
          : (pendingItems.isEmpty && processingItems.isEmpty)
          ? Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight,
              ),
              child: _buildEmptyState(),
            )
          : RefreshIndicator(
              onRefresh: () async {
                final user = authProv.user;
                if (user != null) {
                  await sellerProv.loadSellerOrders(user.id);
                }
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  16,
                  16,
                ),
                children: [
                  if (pendingItems.isNotEmpty) ...[
                    Container(
                      padding: context.rAll(16),
                      decoration: BoxDecoration(
                        color: AppTheme.warningAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.rr(12)),
                        border: Border.all(
                          color: AppTheme.warningAmber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            size: context.ri(20),
                            color: AppTheme.warningAmber,
                          ),
                          SizedBox(width: context.rw(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${pendingItems.length} pending order${pendingItems.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: context.rsp(14),
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                                Text(
                                  'Manage and mark items as processing',
                                  style: TextStyle(
                                    fontSize: context.rsp(12),
                                    color: AppTheme.mutedSteel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ShadButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SellerOrdersScreen(),
                              ),
                            ),
                            child: const Text('Orders'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: context.rh(16)),
                  ],
                  // Every undelivered item gets a verify card — pending ones
                  // can be verified directly too.
                  ...[
                    ...pendingItems.map((item) => (item, true)),
                    ...processingItems.map((item) => (item, false)),
                  ].map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(bottom: context.rh(12)),
                      child: _buildVerifyCard(entry.$1, isPending: entry.$2),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.checkCircle,
            size: context.ri(64),
            color: Colors.grey[300],
          ),
          SizedBox(height: context.rh(16)),
          Text(
            'No pending verifications',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          const Text(
            'Items awaiting delivery code verification will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyCard(OrderItem item, {bool isPending = false}) {
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
              if (item.productThumbnail != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(context.rr(8)),
                  child: SizedBox(
                    width: context.rw(48),
                    height: context.rh(48),
                    child: CachedNetworkImage(
                      imageUrl: item.productThumbnail!,
                      fit: BoxFit.cover,
                      memCacheWidth: 48,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) =>
                          Container(color: AppTheme.warmMist),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rw(6),
                        vertical: context.rh(2),
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warningAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.rr(6)),
                      ),
                      child: Text(
                        isPending ? 'PENDING' : 'AWAITING CODE',
                        style: TextStyle(
                          fontSize: context.rsp(9),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningAmber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => _scanCode(item),
                  leading: Icon(LucideIcons.scanLine, size: context.ri(18)),
                  child: const Text('Scan QR'),
                ),
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                child: ShadButton(
                  onPressed: () => _showManualEntry(item),
                  leading: Icon(LucideIcons.keyboard, size: context.ri(18)),
                  child: const Text('Enter Code'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Checklist of the scanned buyer's pending items from THIS store. All items
/// are pre-selected so "Deliver Selected" processes everything at once;
/// the seller can deselect to deliver only some.
class _BuyerItemsSheet extends StatefulWidget {
  final String buyerId;
  final String? buyerName;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> result) onVerified;

  const _BuyerItemsSheet({
    required this.buyerId,
    required this.buyerName,
    required this.items,
    required this.onVerified,
  });

  @override
  State<_BuyerItemsSheet> createState() => _BuyerItemsSheetState();
}

class _BuyerItemsSheetState extends State<_BuyerItemsSheet> {
  late final Set<String> _selected;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.items.map((i) => i['id'] as String).toSet();
  }

  double get _selectedTotal => widget.items
      .where((i) => _selected.contains(i['id']))
      .fold(
        0.0,
        (sum, i) =>
            sum +
            ((i['price'] as num?) ?? 0).toDouble() *
                ((i['quantity'] as num?) ?? 1).toInt(),
      );

  Future<void> _deliver() async {
    if (_selected.isEmpty || _verifying) return;
    setState(() => _verifying = true);
    try {
      final result = await SellerService.verifyBuyerDeliveries(
        widget.buyerId,
        _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onVerified(result);
    } catch (_) {
      if (mounted) {
        setState(() => _verifying = false);
        widget.onVerified(const {
          'success': false,
          'error': 'Verification failed',
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.buyerName?.isNotEmpty == true) ...[
          Text(
            'Buyer: ${widget.buyerName}',
            style: TextStyle(
              fontSize: context.rsp(13),
              fontWeight: FontWeight.w600,
              color: AppTheme.mutedSteel,
            ),
          ),
          SizedBox(height: context.rh(8)),
        ],
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: widget.items.map((item) {
                final id = item['id'] as String;
                final checked = _selected.contains(id);
                return Padding(
                  padding: EdgeInsets.only(bottom: context.rh(8)),
                  child: GestureDetector(
                    onTap: () => setState(
                      () => checked ? _selected.remove(id) : _selected.add(id),
                    ),
                    child: Container(
                      padding: context.rAll(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(context.rr(12)),
                        border: Border.all(
                          color: checked
                              ? AppTheme.accent.withValues(alpha: 0.5)
                              : AppTheme.whisperBorder,
                        ),
                        color: checked
                            ? AppTheme.accent.withValues(alpha: 0.04)
                            : null,
                      ),
                      child: Row(
                        children: [
                          ShadCheckbox(
                            value: checked,
                            onChanged: (_) => setState(
                              () => checked
                                  ? _selected.remove(id)
                                  : _selected.add(id),
                            ),
                          ),
                          SizedBox(width: context.rw(10)),
                          if (item['product_thumbnail'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                context.rr(8),
                              ),
                              child: SizedBox(
                                width: context.rw(44),
                                height: context.rh(44),
                                child: CachedNetworkImage(
                                  imageUrl: item['product_thumbnail'] as String,
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
                            Container(
                              width: context.rw(44),
                              height: context.rh(44),
                              decoration: BoxDecoration(
                                color: AppTheme.warmMist,
                                borderRadius: BorderRadius.circular(
                                  context.rr(8),
                                ),
                              ),
                              child: Icon(
                                LucideIcons.shoppingBag,
                                size: context.ri(20),
                                color: AppTheme.mutedSteel,
                              ),
                            ),
                          SizedBox(width: context.rw(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['product_title'] as String? ?? 'Item',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: context.rsp(14),
                                  ),
                                ),
                                SizedBox(height: context.rh(2)),
                                Text(
                                  '${formatGhs(((item['price'] as num?) ?? 0).toDouble())} x${(item['quantity'] as num?) ?? 1}',
                                  style: TextStyle(
                                    color: AppTheme.mutedSteel,
                                    fontSize: context.rsp(12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        SizedBox(height: context.rh(12)),
        Row(
          children: [
            Expanded(
              child: Text(
                'Total: ${formatGhs(_selectedTotal)}',
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
            ),
            ShadButton(
              enabled: _selected.isNotEmpty && !_verifying,
              onPressed: _deliver,
              leading: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(LucideIcons.checkCheck, size: context.ri(18)),
              child: Text(
                _selected.length == widget.items.length
                    ? 'Deliver All (${_selected.length})'
                    : 'Deliver Selected (${_selected.length})',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
