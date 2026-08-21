import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../models/seller_review_model.dart';
import '../../services/review_service.dart';
import '../../services/seller_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/review_section.dart';

class SellerReviewsScreen extends ConsumerStatefulWidget {
  const SellerReviewsScreen({super.key});

  @override
  ConsumerState<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends ConsumerState<SellerReviewsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref.read(sellerProvider).loadReviews(user.id);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final sellerProv = ref.read(sellerProvider);
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.8 &&
        sellerProv.hasMoreReviews &&
        !sellerProv.isLoadingMoreReviews) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        sellerProv.loadMoreReviews(user.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerProv = ref.watch(sellerProvider);
    final reviews = sellerProv.reviews;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context,
        title: const Text('Product Reviews'),
        actions: [
          if (reviews.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
                  style: const TextStyle(color: AppTheme.mutedSteel, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: sellerProv.isLoading
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                16,
                16,
              ),
              child: const ListSkeleton(count: 6),
            )
          : RefreshIndicator(
              onRefresh: () async {
                final user = ref.read(authProvider).user;
                if (user != null) {
                  await ref.read(sellerProvider).loadReviews(user.id);
                }
              },
              child: reviews.isEmpty
                  ? ListView(
                      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight),
                      children: [_buildEmptyState()],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                    16,
                    16,
                  ),
                  itemCount: 1 + reviews.length + (sellerProv.hasMoreReviews ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildRatingSummary(reviews);
                    }
                    if (index == reviews.length + 1) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final review = reviews[index - 1];
                    final userId = ref.read(authProvider).user?.id;
                    return _SellerReviewCard(
                      review: review,
                      isOwn: review.reviewerId == userId,
                      onUpdated: () {
                        final user = ref.read(authProvider).user;
                        if (user != null) {
                          ref.read(sellerProvider).loadReviews(user.id);
                        }
                      },
                    );
                  },
                ),
            ),
    );
  }

  Widget _buildRatingSummary(List<ProductReview> reviews) {
    if (reviews.isEmpty) return const SizedBox.shrink();
    final totalRating = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    final avgRating = totalRating / reviews.length;

    // Rating distribution
    final counts = List.generate(5, (i) => reviews.where((r) => r.rating == i + 1).length);

    return Container(
      margin: EdgeInsets.only(bottom: context.rh(16)),
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          // Average score
          Column(
            children: [
              Text(
                avgRating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: context.rsp(36),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                  height: 1,
                ),
              ),
              SizedBox(height: context.rh(4)),
              Row(
                children: List.generate(5, (i) => Icon(
                  i < avgRating.round() ? Icons.star : Icons.star_border,
                  size: context.ri(14),
                  color: i < avgRating.round() ? AppTheme.warningAmber : AppTheme.mutedSteel.withValues(alpha: 0.3),
                )),
              ),
              SizedBox(height: context.rh(2)),
              Text(
                '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
                style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
              ),
            ],
          ),
          SizedBox(width: context.rw(16)),
          // Distribution bars
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = counts[star - 1];
                final fraction = reviews.isNotEmpty ? count / reviews.length : 0.0;
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: context.rh(1.5)),
                  child: Row(
                    children: [
                      SizedBox(
                        width: context.rw(16),
                        child: Text(
                          '$star',
                          style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
                        ),
                      ),
                      Icon(Icons.star, size: context.ri(10), color: AppTheme.warningAmber),
                      SizedBox(width: context.rw(6)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(context.rr(3)),
                          child: LinearProgressIndicator(
                            value: fraction,
                            backgroundColor: AppTheme.whisperBorder,
                            color: AppTheme.warningAmber,
                            minHeight: context.rh(6),
                          ),
                        ),
                      ),
                      SizedBox(width: context.rw(6)),
                      SizedBox(
                        width: context.rw(20),
                        child: Text(
                          '$count',
                          style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.messageSquare, size: context.ri(64), color: AppTheme.mutedSteel.withValues(alpha: 0.5)),
          SizedBox(height: context.rh(16)),
          Text(
            'No reviews yet',
            style: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
          ),
          SizedBox(height: context.rh(8)),
          const Text('Reviews from buyers will appear here', style: TextStyle(color: AppTheme.mutedSteel)),
        ],
      ),
    );
  }
}

class _SellerReviewCard extends StatelessWidget {
  final ProductReview review;
  final bool isOwn;
  final VoidCallback onUpdated;

  const _SellerReviewCard({
    required this.review,
    this.isOwn = false,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: context.rh(12)),
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
              ShadAvatar(
                review.reviewerAvatar?.isNotEmpty == true ? review.reviewerAvatar : null,
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (review.reviewerName ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName ?? 'Anonymous',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                    ),
                    SizedBox(height: context.rh(2)),
                    Row(
                      children: [
                        ...List.generate(5, (i) => Icon(
                          i < review.rating ? Icons.star : Icons.star_border,
                          size: context.ri(14),
                          color: i < review.rating ? AppTheme.warningAmber : AppTheme.mutedSteel.withValues(alpha: 0.3),
                        )),
                        SizedBox(width: context.rw(8)),
                        Text(
                          _formatDate(review.createdAt),
                          style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isOwn)
                PopupMenuButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(LucideIcons.ellipsis, size: context.ri(18), color: AppTheme.mutedSteel),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(fontSize: 14))),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontSize: 14))),
                  ],
                  onSelected: (v) async {
                    if (v == 'edit') {
                      showShadSheet( // ignore: unawaited_futures
                        context: context,
                        builder: (ctx) => ShadSheet(
                          title: const Text('Edit Your Review'),
                          child: ReviewForm(
                            productId: review.productId,
                            existing: review,
                            onSubmitted: () {
                              Navigator.of(ctx).pop();
                              onUpdated();
                            },
                          ),
                        ),
                      );
                    } else if (v == 'delete') {
                      final confirmed = await AppTheme.showGlassDialog<bool>(
                        context: context,
                        title: const Text('Delete Review'),
                        description: const Text('Are you sure you want to delete this review? This cannot be undone.'),
                        actions: [
                          ShadButton.ghost(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ShadButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                      if (confirmed == true) {
                        await ReviewService.deleteReview(review.id);
                        onUpdated();
                      }
                    }
                  },
                ),
            ],
          ),
          if (review.productTitle != null) ...[
            SizedBox(height: context.rh(8)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
              decoration: BoxDecoration(color: AppTheme.warmMist, borderRadius: BorderRadius.circular(context.rr(6))),
              child: Text(
                'On: ${review.productTitle}',
                style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            SizedBox(height: context.rh(10)),
            Text(review.comment!, style: const TextStyle(color: AppTheme.charcoalInk, height: 1.4)),
          ],
          if (review.mediaUrls.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            SizedBox(
              height: context.rh(72),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.mediaUrls.length,
                separatorBuilder: (_, _) => SizedBox(width: context.rw(8)),
                itemBuilder: (context, i) {
                  final url = review.mediaUrls[i];
                  final isVideo = url.contains('.mp4') || url.contains('.mov');
                  return GestureDetector(
                    onTap: () => _showMediaModal(context, review.mediaUrls, i),
                    child: Container(
                      width: context.rw(72), height: context.rh(72),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(context.rr(8)),
                        color: AppTheme.warmMist,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: isVideo
                          ? const Center(child: Icon(LucideIcons.video, color: AppTheme.mutedSteel))
                          : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: 72),
                    ),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: context.rh(8)),
          _SellerReplyThread(review: review, onUpdated: onUpdated),
        ],
      ),
    );
  }

  void _showMediaModal(BuildContext context, List<String> urls, int initialIndex) {
    showShadDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            PageView.builder(
              itemCount: urls.length,
              controller: PageController(initialPage: initialIndex),
              itemBuilder: (_, i) {
                final isVideo = urls[i].contains('.mp4') || urls[i].contains('.mov');
                return InteractiveViewer(
                  child: Center(
                    child: isVideo
                        ? const Icon(LucideIcons.video, size: 64, color: Colors.white70)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: urls[i],
                              fit: BoxFit.contain,
                              memCacheWidth: 400,
                              placeholder: (_, _) => const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                              errorWidget: (_, _, _) => const Icon(
                                LucideIcons.image, color: Colors.white70, size: 48,
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
            Positioned(
              top: 40, right: 16,
              child: ShadIconButton.ghost(
                icon: Icon(LucideIcons.x, color: Colors.white, size: context.ri(28)),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SellerReplyThread extends ConsumerStatefulWidget {
  final ProductReview review;
  final VoidCallback onUpdated;

  const _SellerReplyThread({required this.review, required this.onUpdated});

  @override
  ConsumerState<_SellerReplyThread> createState() => _SellerReplyThreadState();
}

class _SellerReplyThreadState extends ConsumerState<_SellerReplyThread> {
  bool _showReplyField = false;
  final _replyController = TextEditingController();
  bool _isReplying = false;

  @override
  void initState() {
    super.initState();
    if (widget.review.reply != null) {
      _replyController.text = widget.review.reply!;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _submitReply() async {
    if (_replyController.text.trim().isEmpty) return;
    setState(() => _isReplying = true);

    try {
      final userId = ref.read(authProvider).user!.id;
      if (widget.review.replies.isNotEmpty) {
        await SellerService.updateReply(reviewId: widget.review.id, reply: _replyController.text.trim());
      } else {
        await SellerService.replyToReview(
          reviewId: widget.review.id,
          sellerId: userId,
          reply: _replyController.text.trim(),
        );
      }
      setState(() => _showReplyField = false);
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(ShadToast(title: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isReplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = widget.review.reply != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasReply)
          Padding(
            padding: EdgeInsets.only(left: context.rw(12)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: context.rw(2),
                    margin: EdgeInsets.only(bottom: context.rh(8)),
                    color: AppTheme.whisperBorder,
                  ),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Container(
                      padding: context.rAll(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warmMist,
                        borderRadius: BorderRadius.circular(context.rr(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.reply, size: context.ri(14), color: AppTheme.accent),
                              SizedBox(width: context.rw(4)),
                              Text(
                                'Your reply',
                                style: TextStyle(fontSize: context.rsp(12), fontWeight: FontWeight.w600, color: AppTheme.accent),
                              ),
                            ],
                          ),
                          SizedBox(height: context.rh(4)),
                          Text(
                            widget.review.reply!,
                            style: TextStyle(color: AppTheme.charcoalInk, fontSize: context.rsp(13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!_showReplyField)
          Padding(
            padding: EdgeInsets.only(left: context.rw(12), top: context.rh(4)),
            child: GestureDetector(
              onTap: () => setState(() => _showReplyField = true),
              child: Row(
                children: [
                  Icon(hasReply ? LucideIcons.pencil : LucideIcons.reply, size: context.ri(14), color: AppTheme.mutedSteel),
                  SizedBox(width: context.rw(4)),
                  Text(
                    hasReply ? 'Edit reply' : 'Reply',
                    style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        if (_showReplyField) ...[
          SizedBox(height: context.rh(8)),
          Container(
            padding: EdgeInsets.only(left: context.rw(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShadInput(
                  controller: _replyController,
                  placeholder: const Text('Write a reply...'),
                  maxLines: 3,
                ),
                SizedBox(height: context.rh(8)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.ghost(
                      onPressed: () => setState(() {
                        _showReplyField = false;
                        _replyController.text = widget.review.reply ?? '';
                      }),
                      child: const Text('Cancel'),
                    ),
                    SizedBox(width: context.rw(8)),
                    ShadButton(
                      onPressed: _isReplying ? null : _submitReply,
                      child: _isReplying
                          ? SizedBox(width: context.rw(16), height: context.rh(16), child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(hasReply ? 'Update' : 'Reply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
