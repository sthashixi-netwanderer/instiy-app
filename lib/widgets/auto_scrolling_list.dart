import 'dart:async';

import 'package:flutter/material.dart';

/// A horizontal [ListView.builder] that slowly auto-scrolls forward one item
/// at a time when its content overflows the viewport (curated collections,
/// category rails). User drags pause the auto-scroll for a few seconds, and
/// the list loops back to the start once it reaches the end.
class AutoScrollingListView extends StatefulWidget {
  final double height;
  final double itemExtent;
  final EdgeInsetsGeometry padding;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Pause between auto-scroll steps.
  final Duration interval;

  /// Duration of each step animation.
  final Duration stepDuration;

  const AutoScrollingListView({
    super.key,
    required this.height,
    required this.itemExtent,
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
    this.interval = const Duration(milliseconds: 3500),
    this.stepDuration = const Duration(milliseconds: 700),
  });

  @override
  State<AutoScrollingListView> createState() => _AutoScrollingListViewState();
}

class _AutoScrollingListViewState extends State<AutoScrollingListView> {
  final _controller = ScrollController();
  Timer? _timer;

  /// Auto-scrolling resumes at this time after the user interacts.
  DateTime _resumeAt = DateTime.now();

  /// Guards against queuing animations while one is still running.
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _autoStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _autoStep() {
    if (!mounted || _animating || !_controller.hasClients) return;
    final position = _controller.position;
    // Content fits on screen — nothing to auto-scroll.
    if (position.maxScrollExtent <= 0) return;
    if (DateTime.now().isBefore(_resumeAt)) return;

    final target =
        (position.pixels + widget.itemExtent).clamp(0.0, position.maxScrollExtent);
    final atEnd = target >= position.maxScrollExtent - 0.5;
    _animating = true;
    _controller
        .animateTo(
          atEnd ? 0 : target,
          duration: atEnd
              ? widget.stepDuration * 3
              : widget.stepDuration,
          curve: atEnd ? Curves.easeInOutCubic : Curves.easeOutCubic,
        )
        .whenComplete(() => _animating = false);
  }

  bool _onNotification(ScrollNotification notification) {
    // dragDetails is only set for user-initiated scrolls, not animations.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _resumeAt = DateTime.now().add(const Duration(seconds: 5));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          itemCount: widget.itemCount,
          itemExtent: widget.itemExtent,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}
