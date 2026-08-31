import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'instiy_logo_placeholder.dart';

/// A shimmer-animated placeholder for loading states.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.warmMist,
                AppTheme.pureSurface,
                AppTheme.warmMist,
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for a product card (grid item) — a breathing Instiy logo fills
/// the card until the product loads.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: const InstiyLogoPlaceholder(
        width: double.infinity,
        height: double.infinity,
        animate: true,
      ),
    );
  }
}

/// Skeleton for a list tile (notifications, conversations, transactions).
class ListTileSkeleton extends StatelessWidget {
  const ListTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Skeleton(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(width: 160, height: 14),
                const SizedBox(height: 6),
                const Skeleton(width: 100, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Skeleton(width: 40, height: 10),
        ],
      ),
    );
  }
}

/// Skeleton for a chat message bubble.
class MessageBubbleSkeleton extends StatelessWidget {
  final bool isMe;

  const MessageBubbleSkeleton({super.key, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.accent.withValues(alpha: 0.1) : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Skeleton(
              width: isMe ? 120 : 160,
              height: 12,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Skeleton(
              width: isMe ? 40 : 50,
              height: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grid of product card skeletons for loading state.
class ProductGridSkeleton extends StatelessWidget {
  final int count;

  const ProductGridSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: count,
      itemBuilder: (_, _) => const ProductCardSkeleton(),
    );
  }
}

/// A list of ListTile skeletons for loading state.
class ListSkeleton extends StatelessWidget {
  final int count;

  const ListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: List.generate(
          count,
          (_) => const ListTileSkeleton(),
        ),
      ),
    );
  }
}
