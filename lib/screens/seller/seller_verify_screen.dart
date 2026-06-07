import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/order_model.dart';
import '../../utils/responsive.dart';
import 'scanner_screen.dart';

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
          title: Text('Verified! GH\u00a2 ${(result['amount'] as num?)?.toStringAsFixed(2) ?? ''} released to wallet.'),
        ),
      );
      final user = ref.read(authProvider).user;
      if (user != null) {
        prov.loadSellerOrders(user.id);
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
        ShadButton(
          onPressed: () {
            Navigator.of(context).pop();
            _verifyCode(item, codeController.text.trim().toUpperCase());
          },
          child: const Text('Verify'),
        ),
      ],
    );
  }

  void _scanCode(OrderItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          onDetect: (code) => _verifyCode(item, code),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Verify Deliveries')),
        body: const Center(child: Text('Sign in as a seller')),
      );
    }

    final pendingItems = sellerProv.sellerOrders
        .expand((o) => o.items)
        .where((i) => i.deliveryCode != null && i.status == 'pending')
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Verify Deliveries')),
      body: sellerProv.isLoading
          ? const Center(child: CircularProgressIndicator())
          : pendingItems.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () async {
                    final user = authProv.user;
                    if (user != null) {
                      await sellerProv.loadSellerOrders(user.id);
                    }
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: pendingItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildVerifyCard(pendingItems[index]);
                    },
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
                      'GH\u00a2 ${item.price.toStringAsFixed(2)} x${item.quantity}',
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
