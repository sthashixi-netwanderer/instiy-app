import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/wallet_model.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/instiy_logo_placeholder.dart';

/// Full-screen transaction details (receipt) view — replaces the former
/// transaction details dialog on the wallet screen.
class TransactionDetailScreen extends StatefulWidget {
  final WalletTransaction tx;

  const TransactionDetailScreen({super.key, required this.tx});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  /// Order item behind a sale credit (unit price, quantity, thumbnail).
  Map<String, dynamic>? _saleItem;

  WalletTransaction get tx => widget.tx;

  bool get _isCredit => tx.type == 'deposit' || tx.type == 'transfer_in';

  /// Sale credits reference the order item as `SALE-<order_id>-<item_id>`;
  /// the item UUID is the trailing 36 characters.
  String? get _saleItemId {
    final ref = tx.reference;
    if (ref == null || !ref.startsWith('SALE-')) return null;
    if (ref.length < 36 + 5) return null;
    return ref.substring(ref.length - 36);
  }

  String get _typeLabel => tx.type
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');

  @override
  void initState() {
    super.initState();
    _loadSaleItem();
  }

  Future<void> _loadSaleItem() async {
    final itemId = _saleItemId;
    if (itemId == null) return;
    try {
      final data = await SupabaseService.table('order_items')
          .select('product_title, product_thumbnail, quantity, price')
          .eq('id', itemId)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _saleItem = data);
      }
    } catch (_) {
      // Sale breakdown is optional — the receipt stays complete without it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isCredit ? AppTheme.successMoss : AppTheme.destructive;
    final icon = _isCredit ? LucideIcons.arrowDown : LucideIcons.arrowUp;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Transaction Details'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + kToolbarHeight + 24,
          16,
          24,
        ),
        child: Column(
          children: [
            // Amount hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_isCredit ? '+' : '-'}${formatGhs(tx.amount)}',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _typeLabel,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    DateFormat(
                      'MMM d, yyyy - h:mm:ss a',
                    ).format(tx.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sale breakdown — what the buyer paid for and what was released
            if (_saleItem != null) ...[
              _buildSaleBreakdown(),
              const SizedBox(height: 16),
            ],

            // Details card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.mutedSteel,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'Description',
                    value: tx.description ?? '-',
                  ),
                  _DetailRow(
                    label: 'Reference',
                    value: tx.reference ?? '-',
                    copyable: true,
                  ),
                  _DetailRow(label: 'Source', value: tx.source ?? '-'),
                  _DetailRow(
                    label: 'Balance Before',
                    value: formatGhs(tx.balanceBefore),
                  ),
                  _DetailRow(
                    label: 'Balance After',
                    value: formatGhs(tx.balanceAfter),
                  ),
                  _DetailRow(
                    label: 'Transaction ID',
                    value: tx.id,
                    copyable: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Unit price × quantity for the sold item, plus the delivery fee and the
  /// total amount that was actually released to the seller's wallet.
  Widget _buildSaleBreakdown() {
    final item = _saleItem!;
    final title = item['product_title'] as String? ?? 'Item';
    final thumbnail = item['product_thumbnail'] as String?;
    final unitPrice = ((item['price'] as num?) ?? 0).toDouble();
    final quantity = ((item['quantity'] as num?) ?? 1).toInt();
    final subtotal = unitPrice * quantity;
    final fee = tx.amount - subtotal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Item',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.mutedSteel,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: thumbnail != null && thumbnail.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: thumbnail,
                          fit: BoxFit.cover,
                          memCacheWidth: 104,
                          placeholder: (_, _) => const InstiyLogoPlaceholder(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          errorWidget: (_, _, _) => const InstiyLogoPlaceholder(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        )
                      : const InstiyLogoPlaceholder(
                          width: double.infinity,
                          height: double.infinity,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailRow(label: 'Unit Price', value: formatGhs(unitPrice)),
          _DetailRow(label: 'Quantity', value: '$quantity'),
          _DetailRow(label: 'Subtotal', value: formatGhs(subtotal)),
          if (fee > 0.01)
            _DetailRow(label: 'Delivery Fee', value: formatGhs(fee)),
          const Divider(height: 20, color: AppTheme.whisperBorder),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Released to Seller',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
                Text(
                  formatGhs(tx.amount),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successMoss,
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.mutedSteel, fontSize: 13),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.charcoalInk,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (copyable && value != '-')
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ShadToaster.of(context).show(
                        ShadToast(title: Text('$label copied to clipboard!')),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        LucideIcons.copy,
                        size: 14,
                        color: AppTheme.accent,
                      ),
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
