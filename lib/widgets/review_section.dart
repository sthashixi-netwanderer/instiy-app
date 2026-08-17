import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/seller_review_model.dart';
import '../providers/providers.dart';
import '../providers/block_provider.dart';
import '../services/review_service.dart';
import '../utils/responsive.dart';

class ReviewSection extends ConsumerStatefulWidget {
  final String productId;

  const ReviewSection({super.key, required this.productId});

  @override
  ConsumerState<ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends ConsumerState<ReviewSection> {
  List<ProductReview> _reviews = [];
  ProductReview? _myReview;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final userId = ref.read(authProvider).user?.id;
    final reviews = await ReviewService.getProductReviews(widget.productId);
    final filtered = BlockProvider.instance.filterReviews(reviews);
    if (!mounted) return;
    setState(() {
      _reviews = filtered;
      _myReview = userId != null
          ? reviews.where((r) => r.reviewerId == userId).firstOrNull
          : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reviews (${_reviews.length})',
              style: TextStyle(
                fontSize: context.rsp(18),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            if (_myReview != null)
              ShadButton.ghost(
                onPressed: () {
                  final user = ref.read(authProvider).user;
                  if (user == null) {
                    Navigator.of(context).pushNamed('/login');
                    return;
                  }
                  _showReviewDialog(context, existing: _myReview);
                },
                leading: Icon(LucideIcons.pencil, size: context.ri(16)),
                child: const Text('Edit'),
              ),
          ],
        ),
        SizedBox(height: context.rh(12)),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          if (_reviews.isEmpty)
            Container(
              padding: context.rAll(24),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(12)),
              ),
              child: Center(
                child: Text(
                  'No reviews yet. Be the first to review!',
                  style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(14)),
                ),
              ),
            )
          else
            ..._reviews.map((review) => _ReviewCard(
                  review: review,
                  isOwn: review.reviewerId == ref.read(authProvider).user?.id,
                  productId: widget.productId,
                  onUpdated: _loadReviews,
                )),
          SizedBox(height: context.rh(16)),
          if (_myReview == null)
            SizedBox(
              width: double.infinity,
              child: ShadButton.outline(
                onPressed: () {
                  final user = ref.read(authProvider).user;
                  if (user == null) {
                    Navigator.of(context).pushNamed('/login');
                    return;
                  }
                  _showReviewDialog(context);
                },
                leading: Icon(LucideIcons.pencil, size: context.ri(18)),
                child: const Text('Write a Review'),
              ),
            ),
        ],
      ],
    ),
    );
  }

  void _showReviewDialog(BuildContext context, {ProductReview? existing}) {
    showShadSheet(
      context: context,
      builder: (ctx) => ShadSheet(
        title: Text(existing != null ? 'Edit Your Review' : 'Write a Review'),
        child: ReviewForm(
          productId: widget.productId,
          existing: existing,
          onSubmitted: () {
            Navigator.of(ctx).pop();
            _loadReviews();
          },
        ),
      ),
    );
  }
}

class ReviewForm extends ConsumerStatefulWidget {
  final String productId;
  final ProductReview? existing;
  final VoidCallback onSubmitted;

  const ReviewForm({
    super.key,
    required this.productId,
    this.existing,
    required this.onSubmitted,
  });

  @override
  ConsumerState<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<ReviewForm> {
  int _rating = 0;
  final _commentController = TextEditingController();
  final List<File> _newMediaFiles = [];
  final List<String> _existingMediaUrls = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _rating = widget.existing!.rating;
      _commentController.text = widget.existing!.comment ?? '';
      _existingMediaUrls.addAll(widget.existing!.mediaUrls);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final source = await showShadSheet<ImageSource>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Add Media'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.camera, color: AppTheme.accent),
                    title: const Text('Camera'),
                    onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.image, color: AppTheme.successMoss),
                    title: const Text('Gallery'),
                    onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final totalMedia = _existingMediaUrls.length + _newMediaFiles.length;

    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null && totalMedia < 5) {
        setState(() => _newMediaFiles.add(File(picked.path)));
      }
    } else {
      final images = await picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      final remaining = 5 - totalMedia;
      if (images.isNotEmpty) {
        setState(() {
          _newMediaFiles.addAll(
            images.take(remaining).map((x) => File(x.path)),
          );
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please select a rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = ref.read(authProvider).user!.id;

      if (widget.existing != null) {
        await ReviewService.updateReview(
          reviewId: widget.existing!.id,
          rating: _rating,
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
          newMediaFiles: _newMediaFiles.isNotEmpty ? _newMediaFiles : null,
          keepMediaUrls: _existingMediaUrls.isNotEmpty ? _existingMediaUrls : null,
        );
      } else {
        await ReviewService.submitReview(
          productId: widget.productId,
          reviewerId: userId,
          rating: _rating,
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
          mediaFiles: _newMediaFiles,
        );
      }

      widget.onSubmitted();
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMedia = _existingMediaUrls.length + _newMediaFiles.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rw(20), context.rh(20), context.rw(20), MediaQuery.of(context).viewInsets.bottom + context.rh(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = starNum),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.rw(4)),
                  child: Icon(
                    starNum <= _rating ? Icons.star : Icons.star_border,
                    size: context.ri(40),
                    color: starNum <= _rating
                        ? AppTheme.warningAmber
                        : AppTheme.mutedSteel,
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: context.rh(16)),
          ShadInput(
            controller: _commentController,
            maxLines: 3,
            placeholder: const Text('Share your experience with this product...'),
          ),
          SizedBox(height: context.rh(12)),
          if (totalMedia < 5)
            ShadButton.ghost(
              onPressed: _pickMedia,
              leading: Icon(LucideIcons.image, size: context.ri(18)),
              child: const Text('Add Photos/Videos'),
            ),
          if (totalMedia > 0) ...[
            SizedBox(height: context.rh(8)),
            SizedBox(
              height: context.rh(80),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._existingMediaUrls.map((url) => _MediaThumbnail(
                        url: url,
                        onRemove: () => setState(() => _existingMediaUrls.remove(url)),
                      )),
                  ..._newMediaFiles.asMap().entries.map((e) => _LocalMediaThumbnail(
                        file: e.value,
                        onRemove: () => setState(() => _newMediaFiles.removeAt(e.key)),
                      )),
                ],
              ),
            ),
          ],
          SizedBox(height: context.rh(16)),
          SizedBox(
            width: double.infinity,
            height: context.rh(48),
            child: ShadButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? SizedBox(
                      height: context.rh(20), width: context.rw(20),
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.existing != null ? 'Update Review' : 'Submit Review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _MediaThumbnail({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isVideo = url.contains('.mp4') || url.contains('.mov');
    return Stack(
      children: [
        Container(
          width: context.rw(80), height: context.rh(80), margin: EdgeInsets.only(right: context.rw(8)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.rr(8)),
            color: AppTheme.warmMist,
          ),
          clipBehavior: Clip.antiAlias,
          child: isVideo
              ? Center(child: Icon(LucideIcons.video, size: context.ri(24), color: AppTheme.mutedSteel))
              : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: 160),
        ),
        Positioned(
          top: context.rh(2), right: context.rw(10),
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: context.rAll(2),
              decoration: const BoxDecoration(
                color: AppTheme.destructive, shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: context.ri(14), color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalMediaThumbnail extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _LocalMediaThumbnail({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isVideo = ['mp4', 'mov', 'avi', 'webm'].contains(file.path.split('.').last.toLowerCase());
    return Stack(
      children: [
        Container(
          width: context.rw(80), height: context.rh(80), margin: EdgeInsets.only(right: context.rw(8)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.rr(8)),
            color: AppTheme.warmMist,
          ),
          clipBehavior: Clip.antiAlias,
          child: isVideo
              ? Center(child: Icon(LucideIcons.video, size: context.ri(24), color: AppTheme.mutedSteel))
              : Image.file(file, fit: BoxFit.cover),
        ),
        Positioned(
          top: context.rh(2), right: context.rw(10),
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: context.rAll(2),
              decoration: const BoxDecoration(
                color: AppTheme.destructive, shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: context.ri(14), color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  final ProductReview review;
  final bool isOwn;
  final String productId;
  final VoidCallback onUpdated;
  final int depth;

  const _ReviewCard({
    required this.review,
    required this.isOwn,
    required this.productId,
    required this.onUpdated,
    this.depth = 0,
  });

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _showReplyField = false;
  bool _isReplying = false;
  bool _isExpanded = false;
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isReplying = true);
    try {
      final user = ref.read(authProvider).user;
      if (user == null) {
        Navigator.of(context).pushNamed('/login'); // ignore: unawaited_futures
        return;
      }

      await ReviewService.submitReply(
        productId: widget.productId,
        reviewerId: user.id,
        comment: text,
        parentId: widget.review.id,
      );

      _replyController.clear();
      setState(() => _showReplyField = false);
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReplying = false);
    }
  }

  void _showEditDialog() {
    if (widget.review.parentId == null) {
      showShadSheet(
        context: context,
        builder: (ctx) => ShadSheet(
          title: const Text('Edit Your Review'),
          child: ReviewForm(
            productId: widget.productId,
            existing: widget.review,
            onSubmitted: () {
              Navigator.of(ctx).pop();
              widget.onUpdated();
            },
          ),
        ),
      );
    } else {
      final controller = TextEditingController(text: widget.review.comment);
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Edit Reply'),
            content: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ShadInput(
                controller: controller,
                maxLines: 3,
                placeholder: const Text('Edit your reply...'),
              ),
            ),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed: () async {
                  final newText = controller.text.trim();
                  if (newText.isNotEmpty) {
                    final nav = Navigator.of(ctx);
                    await ReviewService.updateReply(widget.review.id, newText);
                    widget.onUpdated();
                    nav.pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTopLevel = widget.depth == 0;
    final currentUserId = ref.read(authProvider).user?.id;

    return Container(
      margin: EdgeInsets.only(bottom: isTopLevel ? context.rh(16) : context.rh(8), top: isTopLevel ? 0 : context.rh(8)),
      padding: isTopLevel ? context.rAll(16) : EdgeInsets.zero,
      decoration: isTopLevel
          ? BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(16)),
              border: Border.all(color: AppTheme.whisperBorder),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShadAvatar(
                widget.review.reviewerAvatar?.isNotEmpty == true ? widget.review.reviewerAvatar : null,
                size: widget.depth > 0 ? Size(context.rw(32), context.rh(32)) : Size(context.rw(40), context.rh(40)),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (widget.review.reviewerName ?? 'U')[0].toUpperCase(),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.rsp(14)),
                ),
              ),
              SizedBox(width: context.rw(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.review.reviewerName ?? 'Anonymous',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: widget.depth > 0 ? context.rsp(13) : context.rsp(14),
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    Row(
                      children: [
                        if (widget.review.rating > 0) ...[
                          ...List.generate(5, (i) => Icon(
                            i < widget.review.rating ? Icons.star : Icons.star_border,
                            size: context.ri(12),
                            color: i < widget.review.rating
                                ? AppTheme.warningAmber
                                : AppTheme.mutedSteel,
                          )),
                          SizedBox(width: context.rw(6)),
                        ],
                        Text(
                          _formatDate(widget.review.createdAt),
                          style: TextStyle(fontSize: context.rsp(10), color: AppTheme.mutedSteel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.isOwn)
                PopupMenuButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(LucideIcons.ellipsis, size: context.ri(18), color: AppTheme.mutedSteel),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(fontSize: context.rsp(14)))),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontSize: context.rsp(14)))),
                  ],
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _showEditDialog();
                    } else if (v == 'delete') {
                      final confirmed = await AppTheme.showGlassDialog<bool>(
                        context: context,
                        title: const Text('Delete Comment'),
                        description: const Text('Are you sure you want to delete this?'),
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
                        await ReviewService.deleteReview(widget.review.id);
                        widget.onUpdated();
                      }
                    }
                  },
                ),
            ],
          ),
          if (widget.review.comment != null && widget.review.comment!.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            Text(
              widget.review.comment!,
              style: TextStyle(
                color: AppTheme.charcoalInk,
                fontSize: widget.depth > 0 ? context.rsp(13) : context.rsp(14),
                height: 1.4,
              ),
            ),
          ],
          if (widget.review.mediaUrls.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            SizedBox(
              height: context.rh(72),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.review.mediaUrls.length,
                separatorBuilder: (_, _) => SizedBox(width: context.rw(8)),
                itemBuilder: (context, i) {
                  final url = widget.review.mediaUrls[i];
                  final isVideo = url.contains('.mp4') || url.contains('.mov');
                  return GestureDetector(
                    onTap: () => _showMediaModal(context, widget.review.mediaUrls, i),
                    child: Container(
                      width: context.rw(72), height: context.rh(72),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(context.rr(8)),
                        color: AppTheme.warmMist,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: isVideo
                          ? Center(child: Icon(LucideIcons.video, size: context.ri(24), color: AppTheme.mutedSteel))
                          : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: 160),
                    ),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: context.rh(6)),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  final user = ref.read(authProvider).user;
                  if (user == null) {
                    Navigator.of(context).pushNamed('/login');
                    return;
                  }
                  setState(() => _showReplyField = !_showReplyField);
                },
                child: Row(
                  children: [
                    Icon(LucideIcons.reply, size: context.ri(14), color: AppTheme.mutedSteel),
                    SizedBox(width: context.rw(4)),
                    Text(
                      _showReplyField ? 'Cancel' : 'Reply',
                      style: TextStyle(
                        fontSize: context.rsp(12),
                        color: AppTheme.mutedSteel,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showReplyField) ...[
            SizedBox(height: context.rh(8)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _replyController,
                    maxLines: 2,
                    placeholder: const Text('Write a reply...'),
                  ),
                ),
                SizedBox(width: context.rw(8)),
                ShadButton(
                  onPressed: _isReplying ? null : _submitReply,
                  size: ShadButtonSize.sm,
                  child: _isReplying
                      ? SizedBox(width: context.rw(16), height: context.rh(16), child: const CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reply'),
                ),
              ],
            ),
          ],
          if (widget.depth >= 2 && widget.review.replies.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(LucideIcons.messageSquare, size: context.ri(14), color: AppTheme.accent),
              label: Text(
                'Show More Replies (${widget.review.replies.length})',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReviewRepliesScreen(
                      parentReview: widget.review,
                      productId: widget.productId,
                      onUpdated: widget.onUpdated,
                    ),
                  ),
                );
              },
            ),
          ] else if (widget.depth < 2 && widget.review.replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 1.5,
                    margin: EdgeInsets.only(
                      left: widget.depth == 0 ? 19 : 15,
                      right: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.whisperBorder,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The first reply (index 0) is always visible
                        _ReviewCard(
                          review: widget.review.replies.first,
                          isOwn: widget.review.replies.first.reviewerId == currentUserId,
                          productId: widget.productId,
                          onUpdated: widget.onUpdated,
                          depth: widget.depth + 1,
                        ),
                        // The rest of the replies are only shown if expanded
                        if (_isExpanded)
                          ...widget.review.replies.skip(1).map((child) {
                            return _ReviewCard(
                              review: child,
                              isOwn: child.reviewerId == currentUserId,
                              productId: widget.productId,
                              onUpdated: widget.onUpdated,
                              depth: widget.depth + 1,
                            );
                          }),
                        // Expand/collapse button if there's more than 1 reply
                        if (widget.review.replies.length > 1) ...[
                          SizedBox(height: context.rh(4)),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.only(left: context.rw(4), top: context.rh(4), bottom: context.rh(4)),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                              size: context.ri(14),
                              color: AppTheme.accent,
                            ),
                            label: Text(
                              _isExpanded
                                  ? 'Collapse replies'
                                  : 'Show ${widget.review.replies.length - 1} more reply(s)',
                              style: TextStyle(
                                fontSize: context.rsp(12),
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accent,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isExpanded = !_isExpanded;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMediaModal(BuildContext context, List<String> urls, int initialIndex) {
    showDialog(
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
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
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

class ReviewRepliesScreen extends ConsumerWidget {
  final ProductReview parentReview;
  final String productId;
  final VoidCallback onUpdated;

  const ReviewRepliesScreen({
    super.key,
    required this.parentReview,
    required this.productId,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Replies Thread'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'CONVERSATION THREAD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.mutedSteel,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            _ReviewCard(
              review: parentReview,
              isOwn: parentReview.reviewerId == ref.read(authProvider).user?.id,
              productId: productId,
              onUpdated: onUpdated,
              depth: 0,
            ),
          ],
        ),
      ),
    );
  }
}
