import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/wallet_model.dart';
import '../../utils/formatters.dart';

/// Full-screen transaction details (receipt) view — replaces the former
/// transaction details dialog on the wallet screen.
class TransactionDetailScreen extends StatelessWidget {
  final WalletTransaction tx;

  const TransactionDetailScreen({super.key, required this.tx});

  bool get _isCredit => tx.type == 'deposit' || tx.type == 'transfer_in';

  String get _typeLabel => tx.type
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');

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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    DateFormat('MMM d, yyyy - h:mm:ss a').format(tx.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

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
                  _DetailRow(label: 'Description', value: tx.description ?? '-'),
                  _DetailRow(label: 'Reference', value: tx.reference ?? '-', copyable: true),
                  _DetailRow(label: 'Source', value: tx.source ?? '-'),
                  _DetailRow(label: 'Balance Before', value: formatGhs(tx.balanceBefore)),
                  _DetailRow(label: 'Balance After', value: formatGhs(tx.balanceAfter)),
                  _DetailRow(label: 'Transaction ID', value: tx.id, copyable: true),
                ],
              ),
            ),
          ],
        ),
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
              style: const TextStyle(
                color: AppTheme.mutedSteel,
                fontSize: 13,
              ),
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
                        ShadToast(
                          title: Text('$label copied to clipboard!'),
                        ),
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
