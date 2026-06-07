import 'dart:async';
import 'package:flutter/material.dart';

class DiscountCountdown extends StatefulWidget {
  final DateTime? endDate;
  final TextStyle? style;

  const DiscountCountdown({super.key, this.endDate, this.style});

  @override
  State<DiscountCountdown> createState() => _DiscountCountdownState();
}

class _DiscountCountdownState extends State<DiscountCountdown> {
  Timer? _timer;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _updateLabel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateLabel();
    });
  }

  @override
  void didUpdateWidget(DiscountCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endDate != widget.endDate) {
      _updateLabel();
    }
  }

  void _updateLabel() {
    final endDate = widget.endDate;
    if (endDate == null) {
      _label = '';
      return;
    }

    final now = DateTime.now();
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final diff = end.difference(now);

    if (diff.isNegative) {
      _label = '';
      return;
    }

    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);

    if (days > 0) {
      _label = '${days}d ${hours}h';
    } else if (hours > 0) {
      _label = '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    } else {
      _label = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_label.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 9, color: widget.style?.color ?? Colors.white),
        const SizedBox(width: 2),
        Text(
          _label,
          style: widget.style ?? const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
