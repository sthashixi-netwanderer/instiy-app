import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/order_model.dart';
import '../../utils/responsive.dart';
import 'scanner_screen.dart';
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
          title: Text('Verified! ${formatGhs((result['amount'] as num?) ?? 0)} released to wallet.'),
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                      _verifyCode(item, codeController.text.trim().toUpperCase());
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
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(autoClose: true),
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _verifyCode(item, code);
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Verify Deliveries')),
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
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Verify Deliveries')),
      body: sellerProv.isLoading
          ? const Center(child: CircularProgressIndicator())
          : (pendingItems.isEmpty && processingItems.isEmpty)
              ? Padding(
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight),
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
                            border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.clock, size: context.ri(20), color: AppTheme.warningAmber),
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
                                      'Mark as processing in Orders to verify',
                                      style: TextStyle(
                                        fontSize: context.rsp(12),
                                        color: AppTheme.mutedSteel,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ShadButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Orders'),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: context.rh(16)),
                      ],
                      if (processingItems.isEmpty)
                        _buildEmptyState()
                      else
                        ...processingItems.map((item) => Padding(
                          padding: EdgeInsets.only(bottom: context.rh(12)),
                          child: _buildVerifyCard(item),
                        )),
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
          Icon(LucideIcons.checkCircle, size: context.ri(64), color: Colors.grey[300]),
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

  Widget _buildVerifyCard(OrderItem item) {
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
                      placeholder: (_, _) => Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) => Container(color: AppTheme.warmMist),
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
                      style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(13)),
                    ),
                    SizedBox(height: context.rh(2)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(2)),
                      decoration: BoxDecoration(
                        color: AppTheme.warningAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.rr(6)),
                      ),
                      child: Text(
                        'AWAITING CODE',
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
