import 'package:intl/intl.dart';

/// Formats a number with thousands separators and two decimal places (e.g. 1,000.00).
String formatCurrency(num amount) {
  final formatter = NumberFormat('#,##0.00', 'en_US');
  return formatter.format(amount);
}

/// Formats amount with GH₵ symbol (e.g. GH₵ 1,000.00).
String formatGhs(num amount) {
  return 'GH\u20B5 ${formatCurrency(amount)}';
}
