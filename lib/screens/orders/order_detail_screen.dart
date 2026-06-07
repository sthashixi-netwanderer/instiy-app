import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/order_model.dart';
import '../../services/supabase_service.dart';
import '../../widgets/skeleton.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Order? _order;
  bool _isLoading = true;
  RealtimeChannel? _itemsChannel;

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _subscribeToOrderItems();
  }

  void _subscribeToOrderItems() {
    _itemsChannel = SupabaseService.client
        .channel('order-detail:${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) => _loadOrder(),
        );
    _itemsChannel!.subscribe();
  }

  @override
  void dispose() {
    if (_itemsChannel != null) {
      SupabaseService.client.removeChannel(_itemsChannel!);
    }
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final order = await ref.read(orderProvider.notifier).loadOrder(widget.orderId);
      if (mounted) {
        setState(() {
          _order = order;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Order Details')),
      body: _isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 6))
          : _order == null
              ? const Center(child: Text('Order not found'))
              : RefreshIndicator(
                  onRefresh: _loadOrder,
                  child: ListView(
                    padding: context.rAll(16),
                    children: [
                      _buildOrderHeader(),
                      SizedBox(height: context.rh(20)),
                      ..._order!.items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Padding(
                          padding: EdgeInsets.only(top: index > 0 ? context.rh(16) : 0),
                          child: _buildItemCard(item),
                        );
                      }),
                      if (_order!.status == 'pending') ...[
                        SizedBox(height: context.rh(24)),
                        ShadButton.destructive(
                          onPressed: _confirmCancelOrder,
                          child: const Text(
                            'Cancel Order',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Future<void> _confirmCancelOrder() async {
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Cancel Order'),
      description: const Text('Are you sure you want to cancel this order? This will refund the total amount to your wallet.'),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No, Keep Order'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes, Cancel'),
        ),
      ],
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await ref.read(orderProvider.notifier).cancelOrder(widget.orderId);
        await _loadOrder();
        if (!mounted) return;
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Order cancelled successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast(title: Text('Failed to cancel order: $e')),
        );
      }
    }
  }

  Widget _buildOrderHeader() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${_order!.id.substring(0, 8).toUpperCase()}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: context.rsp(18),
                  color: AppTheme.charcoalInk,
                ),
              ),
              Container(
                padding: context.rPadding(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(_order!.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(context.rr(12)),
                ),
                child: Text(
                  _order!.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: context.rsp(11),
                    fontWeight: FontWeight.w600,
                    color: _statusColor(_order!.status),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(12)),
          if (_order!.deliveryFee > 0) ...[
            Row(
              children: [
                const Text('Subtotal: ', style: TextStyle(color: AppTheme.mutedSteel)),
                Text(
                  'GH\u00a2 ${formatCurrency(_order!.totalAmount - _order!.deliveryFee)}',
                  style: const TextStyle(color: AppTheme.charcoalInk),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Delivery Fee: ', style: TextStyle(color: AppTheme.mutedSteel)),
                Text(
                  'GH\u00a2 ${formatCurrency(_order!.deliveryFee)}',
                  style: const TextStyle(color: AppTheme.charcoalInk),
                ),
              ],
            ),
          ],
          Row(
            children: [
              const Text('Total: ', style: TextStyle(color: AppTheme.mutedSteel)),
              Text(
                'GH\u00a2 ${formatCurrency(_order!.totalAmount)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.rsp(16)),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Date: ', style: TextStyle(color: AppTheme.mutedSteel)),
              Text(
                DateFormat('MMM d, yyyy').format(_order!.createdAt),
                style: const TextStyle(color: AppTheme.charcoalInk),
              ),
            ],
          ),
          if (_order!.deliveryMode != null) ...[
            Row(
              children: [
                const Text('Delivery Mode: ', style: TextStyle(color: AppTheme.mutedSteel)),
                Text(
                  _order!.deliveryMode!.toUpperCase(),
                  style: const TextStyle(color: AppTheme.charcoalInk),
                ),
              ],
            ),
            if (_order!.deliveryMode == 'delivery' && _order!.deliveryInstitution != null)
              Row(
                children: [
                  const Text('Delivery Campus: ', style: TextStyle(color: AppTheme.mutedSteel)),
                  Text(
                    _order!.deliveryInstitution!,
                    style: const TextStyle(color: AppTheme.charcoalInk, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(OrderItem item) {
    final hasDeliveryCode = item.deliveryCode != null && item.status == 'pending';

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
                    width: context.rw(50),
                    height: context.rh(50),
                    child: CachedNetworkImage(
                      imageUrl: item.productThumbnail!,
                      fit: BoxFit.cover,
                      memCacheWidth: 50,
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
                    ),
                    SizedBox(height: context.rh(4)),
                    Text(
                      'GH\u00a2 ${item.price.toStringAsFixed(2)} x${item.quantity}',
                      style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(13)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: context.rPadding(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(item.status ?? 'pending').withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(context.rr(8)),
                ),
                child: Text(
                  (item.status ?? 'pending').toUpperCase(),
                  style: TextStyle(
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                    color: _statusColor(item.status ?? 'pending'),
                  ),
                ),
              ),
            ],
          ),
          if (hasDeliveryCode)
            Padding(
              padding: EdgeInsets.only(top: context.rh(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: context.rAll(16),
                    decoration: BoxDecoration(
                      color: AppTheme.warmMist,
                      borderRadius: BorderRadius.circular(context.rr(12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Center(
                          child: QrImageView(
                            data: item.deliveryCode!,
                            version: QrVersions.auto,
                            size: context.rw(160),
                            backgroundColor: Colors.white,
                          ),
                        ),
                        SizedBox(height: context.rh(12)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Delivery Code: ${item.deliveryCode}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: context.rsp(18),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  color: AppTheme.charcoalInk,
                                ),
                              ),
                            ),
                            SizedBox(width: context.rw(8)),
                            ShadIconButton.outline(
                              icon: Icon(LucideIcons.copy, size: context.ri(20)),
                              foregroundColor: AppTheme.accent,
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: item.deliveryCode!));
                                if (!mounted) return;
                                if (context.mounted) {
                                  ShadToaster.of(context).show(
                                    ShadToast(
                                      title: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(LucideIcons.check,
                                              color: AppTheme.successMoss, size: context.ri(18)),
                                          SizedBox(width: context.rw(8)),
                                          const Text('Code copied'),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: context.rh(4)),
                        Text(
                          'Share this code with the seller upon delivery',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
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
