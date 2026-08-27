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

/// Formats call duration in WhatsApp style.
/// If >= 60 minutes (3600s), resolves in hours (e.g. "1 hr 15 min 20 sec", "2 hrs 5 min").
/// If < 60 minutes, resolves in minutes/seconds (e.g. "4 min 23 sec", "45 sec").
String formatCallDuration(int totalSeconds) {
  if (totalSeconds <= 0) return '';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    final hrUnit = hours == 1 ? 'hr' : 'hrs';
    if (minutes > 0 && seconds > 0) {
      final minUnit = minutes == 1 ? 'min' : 'mins';
      final secUnit = seconds == 1 ? 'sec' : 'secs';
      return '$hours $hrUnit $minutes $minUnit $seconds $secUnit';
    } else if (minutes > 0) {
      final minUnit = minutes == 1 ? 'min' : 'mins';
      return '$hours $hrUnit $minutes $minUnit';
    } else if (seconds > 0) {
      final secUnit = seconds == 1 ? 'sec' : 'secs';
      return '$hours $hrUnit $seconds $secUnit';
    } else {
      return '$hours $hrUnit';
    }
  } else if (minutes > 0) {
    final minUnit = minutes == 1 ? 'min' : 'mins';
    if (seconds > 0) {
      final secUnit = seconds == 1 ? 'sec' : 'secs';
      return '$minutes $minUnit $seconds $secUnit';
    } else {
      return '$minutes $minUnit';
    }
  } else {
    final secUnit = seconds == 1 ? 'sec' : 'secs';
    return '$seconds $secUnit';
  }
}

/// Compact format (e.g. "1h 15m 20s", "4m 23s", "45s").
String formatCallDurationCompact(int totalSeconds) {
  if (totalSeconds <= 0) return '';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  } else if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  } else {
    return '${seconds}s';
  }
}
