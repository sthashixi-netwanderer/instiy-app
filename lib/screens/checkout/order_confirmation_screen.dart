import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/app_theme.dart';
import '../../models/cart_model.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_button.dart';
import '../../widgets/responsive_layout.dart';

/// Pre-payment confirmation screen shown between checkout and placing the
/// order. Displays every detail of the order (items, delivery, payment and
/// totals) and lets the user tap Proceed to actually place it. All placement
/// logic stays in the checkout screen — it is invoked through [onProceed],
/// which must return true when the order was placed successfully.
class OrderConfirmationScreen extends StatefulWidget {
  final List<CartItem> items;
  final String deliveryMode; // 'pickup' | 'delivery'
  final String? deliveryInstitution;
  final String paymentMethod; // 'wallet' | 'paystack'
  final double subtotal;
  final double deliveryFee;
  final Future<bool> Function() onProceed;

  const OrderConfirmationScreen({
    super.key,
    required this.items,
    required this.deliveryMode,
    required this.deliveryInstitution,
    required this.paymentMethod,
    required this.subtotal,
    required this.deliveryFee,
    required this.onProceed,
  });

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  bool _isProcessing = false;

  double get _total => widget.subtotal + widget.deliveryFee;

  Future<void> _proceed() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final placed = await widget.onProceed();
    if (!mounted) return; // success path pops the whole stack already
    if (!placed) {
      // Checkout already surfaced the error toast — go back to the form.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Confirm Order')),
      bottomNavigationBar: Container(
        padding: context.rAll(20),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${formatGhs(_total)} total • tap Proceed to place your order',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  color: AppTheme.mutedSteel,
                ),
              ),
              SizedBox(height: context.rh(10)),
              AppButton(
                onPressed: _isProcessing ? null : _proceed,
                loading: _isProcessing,
                child: Text(
                  'Proceed',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          context.rw(16),
          MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
          context.rw(16),
          context.rh(16),
        ),
        children: [
          _buildSectionTitle('Order Items'),
          _buildItemsCard(),
          SizedBox(height: context.rh(16)),
          _buildSectionTitle('Delivery'),
          _buildDeliveryCard(),
          SizedBox(height: context.rh(16)),
          _buildSectionTitle('Payment'),
          _buildPaymentCard(),
          SizedBox(height: context.rh(16)),
          _buildSectionTitle('Summary'),
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(left: context.rw(4), bottom: context.rh(8)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: context.rsp(14),
          fontWeight: FontWeight.w600,
          color: AppTheme.charcoalInk,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: child,
    );
  }

  Widget _buildItemsCard() {
    return _card(
      child: Column(
        children: [
          for (var i = 0; i < widget.items.length; i++) ...[
            if (i > 0) SizedBox(height: context.rh(12)),
            _buildItemRow(widget.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(CartItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.rr(10)),
          child: SizedBox(
            width: context.rw(52),
            height: context.rw(52),
            child: item.thumbnail != null && item.thumbnail!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.thumbnail!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: AppTheme.cleanBackgroundAlt,
                      child: Icon(
                        LucideIcons.image,
                        size: context.ri(18),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: AppTheme.cleanBackgroundAlt,
                      child: Icon(
                        LucideIcons.image,
                        size: context.ri(18),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                  )
                : Container(
                    color: AppTheme.cleanBackgroundAlt,
                    child: Icon(
                      LucideIcons.image,
                      size: context.ri(18),
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
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.rsp(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
              if (item.sellerName != null && item.sellerName!.isNotEmpty) ...[
                SizedBox(height: context.rh(2)),
                Text(
                  item.sellerName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.rsp(12),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
              SizedBox(height: context.rh(2)),
              Text(
                'Qty ${item.quantity}',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: context.rw(8)),
        Text(
          formatGhs(item.totalPrice),
          style: TextStyle(
            fontSize: context.rsp(14),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryCard() {
    final isPickup = widget.deliveryMode == 'pickup';
    return _card(
      child: Row(
        children: [
          Container(
            width: context.ri(36),
            height: context.ri(36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(
              isPickup ? LucideIcons.store : LucideIcons.truck,
              size: context.ri(18),
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPickup ? 'Pickup' : 'Campus Delivery',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(2)),
                Text(
                  isPickup
                      ? 'Pick up directly from the seller'
                      : 'Deliver to ${widget.deliveryInstitution ?? 'your campus'}',
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
    );
  }

  Widget _buildPaymentCard() {
    final isWallet = widget.paymentMethod == 'wallet';
    return _card(
      child: Row(
        children: [
          Container(
            width: context.ri(36),
            height: context.ri(36),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(
              isWallet ? LucideIcons.wallet : LucideIcons.creditCard,
              size: context.ri(18),
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWallet ? 'Wallet' : 'Paystack',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(2)),
                Text(
                  isWallet
                      ? 'Pay directly from your Instiy wallet'
                      : 'Card payment via Paystack',
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
    );
  }

  Widget _buildSummaryCard() {
    Widget summaryRow(String label, String value, {bool isTotal = false}) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: context.rh(4)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: context.rsp(isTotal ? 15 : 13),
                  fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
                  color: isTotal ? AppTheme.charcoalInk : AppTheme.mutedSteel,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: context.rsp(isTotal ? 15 : 13),
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                color: isTotal ? AppTheme.charcoalInk : AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        children: [
          summaryRow('Subtotal (${widget.items.length} ${widget.items.length == 1 ? 'item' : 'items'})', formatGhs(widget.subtotal)),
          summaryRow('Delivery fee', widget.deliveryFee > 0 ? formatGhs(widget.deliveryFee) : 'Free'),
          Divider(color: AppTheme.whisperBorder, height: context.rh(20)),
          summaryRow('Total', formatGhs(_total), isTotal: true),
        ],
      ),
    );
  }
}
