import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';
import '../models/service_model.dart';
import '../services/service_service.dart';
import '../providers/providers.dart';

/// Reviews list + write/edit/delete-own flow for a service. Mirrors the
/// product ReviewSection pattern (bottom-sheet form, star input, ellipsis
/// menu on your own review) without threaded replies.
class ServiceReviewSection extends ConsumerStatefulWidget {
  final String serviceId;
  final String providerId;
  final VoidCallback? onReviewsChanged;

  const ServiceReviewSection({
    super.key,
    required this.serviceId,
    required this.providerId,
    this.onReviewsChanged,
  });

  @override
  ConsumerState<ServiceReviewSection> createState() =>
      _ServiceReviewSectionState();
}

class _ServiceReviewSectionState extends ConsumerState<ServiceReviewSection> {
  List<ServiceReview> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await ServiceService.getServiceReviews(widget.serviceId);
      if (!mounted) return;
      // The viewer's own review always sits at the top so it is visible
      // on every visit; everything else keeps its newest-first order.
      final uid = _currentUserId;
      setState(() => _reviews = [
            ...reviews.where((r) => r.reviewerId == uid),
            ...reviews.where((r) => r.reviewerId != uid),
          ]);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? get _currentUserId => ref.read(authProvider).user?.id;

  ServiceReview? get _myReview {
    final uid = _currentUserId;
    if (uid == null) return null;
    for (final r in _reviews) {
      if (r.reviewerId == uid) return r;
    }
    return null;
  }

  void _openForm({ServiceReview? existing}) {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    showShadSheet(
      context: context,
      builder: (ctx) => ShadSheet(
        title: Text(existing == null ? 'Write a Review' : 'Edit Your Review'),
        child: _ServiceReviewForm(
          existing: existing,
          onSubmit: (rating, comment, keepUrls, newFiles) async {
            if (existing == null) {
              await ServiceService.submitServiceReview(
                serviceId: widget.serviceId,
                providerId: widget.providerId,
                rating: rating,
                comment: comment,
                imageFiles: newFiles,
              );
            } else {
              await ServiceService.updateServiceReview(
                existing.id,
                rating: rating,
                comment: comment,
                keepMediaUrls: keepUrls,
                newImageFiles: newFiles,
              );
            }
          },
        ),
      ),
    ).then((submitted) {
      if (submitted == true) {
        _loadReviews();
        widget.onReviewsChanged?.call();
      }
    });
  }

  Future<void> _deleteReview(ServiceReview review) async {
    final isReply = review.parentId != null;
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: Text(isReply ? 'Delete Comment' : 'Delete Review'),
      description: Text(
        isReply
            ? 'Are you sure you want to delete this?'
            : 'Your review will be removed permanently. This cannot be undone.',
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton(
          backgroundColor: AppTheme.destructive,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    try {
      await ServiceService.deleteServiceReview(review.id);
      await _loadReviews();
      widget.onReviewsChanged?.call();
      if (mounted && !isReply) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Review deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Couldn\'t delete review: $e')),
        );
      }
    }
  }

  /// Opens the edit sheet for a top-level review, or the edit dialog for a
  /// reply — the card delegates here so all writes live in one place.
  void _editReview(ServiceReview review) {
    if (review.parentId == null) {
      _openForm(existing: review);
      return;
    }
    final controller = TextEditingController(text: review.comment);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Reply'),
          content: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
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
                  await ServiceService.updateServiceReply(
                    review.id,
                    newText,
                  );
                  await _loadReviews();
                  widget.onReviewsChanged?.call();
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

  Future<void> _submitReply(ServiceReview parent, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final user = ref.read(authProvider).user;
    if (user == null) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    await ServiceService.submitServiceReply(
      serviceId: widget.serviceId,
      comment: trimmed,
      parentId: parent.id,
    );
    await _loadReviews();
    widget.onReviewsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final myReview = _myReview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Reviews (${_reviews.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(16),
                color: AppTheme.charcoalInk,
              ),
            ),
            const Spacer(),
            if (myReview != null)
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: () => _openForm(existing: myReview),
                child: const Text('Edit'),
              ),
          ],
        ),
        SizedBox(height: context.rh(12)),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_reviews.isEmpty)
          Text(
            'No reviews yet. Be the first to share your experience.',
            style: TextStyle(
              color: AppTheme.mutedSteel,
              fontSize: context.rsp(13),
            ),
          )
        else
          ..._reviews.map(
            (review) => _ServiceReviewCard(
              review: review,
              isOwn: review.reviewerId == _currentUserId,
              serviceId: widget.serviceId,
              onEditReview: _editReview,
              onDeleteReview: _deleteReview,
              onReplyTo: _submitReply,
            ),
          ),
        SizedBox(height: context.rh(12)),
        if (myReview == null)
          SizedBox(
            width: double.infinity,
            child: ShadButton.outline(
              onPressed: () => _openForm(),
              child: const Text('Write a Review'),
            ),
          ),
      ],
    );
  }
}

/// One review with threaded replies, matching the product detail review
/// cards: reply toggle + inline field, nested replies with expand/collapse,
/// and a full thread screen once nesting runs deep.
class _ServiceReviewCard extends ConsumerStatefulWidget {
  final ServiceReview review;
  final bool isOwn;
  final String serviceId;
  final void Function(ServiceReview review) onEditReview;
  final void Function(ServiceReview review) onDeleteReview;
  final Future<void> Function(ServiceReview parent, String text) onReplyTo;
  final int depth;

  const _ServiceReviewCard({
    required this.review,
    required this.isOwn,
    required this.serviceId,
    required this.onEditReview,
    required this.onDeleteReview,
    required this.onReplyTo,
    this.depth = 0,
  });

  @override
  ConsumerState<_ServiceReviewCard> createState() => _ServiceReviewCardState();
}

class _ServiceReviewCardState extends ConsumerState<_ServiceReviewCard> {
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
      await widget.onReplyTo(widget.review, text);
      _replyController.clear();
      if (mounted) setState(() => _showReplyField = false);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Couldn\'t post reply: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReplying = false);
    }
  }

  void _toggleReplyField() {
    final user = ref.read(authProvider).user;
    if (user == null) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    setState(() => _showReplyField = !_showReplyField);
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final isTopLevel = widget.depth == 0;
    final currentUserId = ref.read(authProvider).user?.id;

    return Container(
      margin: EdgeInsets.only(
        bottom: isTopLevel ? context.rh(12) : context.rh(8),
        top: isTopLevel ? 0 : context.rh(8),
      ),
      padding: isTopLevel ? context.rAll(14) : EdgeInsets.zero,
      decoration: isTopLevel
          ? BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(12)),
              border: Border.all(color: AppTheme.whisperBorder),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShadAvatar(
                (review.reviewerAvatar != null &&
                        review.reviewerAvatar!.isNotEmpty)
                    ? review.reviewerAvatar
                    : null,
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (review.reviewerName ?? 'U')[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: context.rsp(12),
                  ),
                ),
              ),
              SizedBox(width: context.rw(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName ?? 'Anonymous',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.rsp(13),
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    Row(
                      children: [
                        if (review.rating > 0)
                          for (var i = 1; i <= 5; i++)
                            Icon(
                              i <= review.rating
                                  ? Icons.star
                                  : Icons.star_border,
                              size: context.ri(13),
                              color: Colors.amber,
                            ),
                        if (review.rating > 0)
                          SizedBox(width: context.rw(6)),
                        Text(
                          _timeAgo(review.createdAt),
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.isOwn)
                PopupMenuButton<String>(
                  icon: Icon(
                    LucideIcons.ellipsis,
                    size: context.ri(18),
                    color: AppTheme.mutedSteel,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') widget.onEditReview(review);
                    if (value == 'delete') widget.onDeleteReview(review);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 16,
                            color: AppTheme.destructive,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.destructive),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            SizedBox(height: context.rh(10)),
            Text(
              review.comment!,
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
                height: 1.5,
              ),
            ),
          ],
          if (review.mediaUrls.isNotEmpty) ...[
            SizedBox(height: context.rh(10)),
            SizedBox(
              height: context.rh(72),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.mediaUrls.length,
                separatorBuilder: (_, _) => SizedBox(width: context.rw(8)),
                itemBuilder: (context, i) {
                  final url = review.mediaUrls[i];
                  return GestureDetector(
                    onTap: () => _showReviewImage(context, url),
                    child: Container(
                      width: context.rw(72),
                      height: context.rh(72),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(context.rr(8)),
                        color: AppTheme.warmMist,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: context.rh(6)),
          GestureDetector(
            onTap: _toggleReplyField,
            child: Row(
              children: [
                Icon(
                  LucideIcons.reply,
                  size: context.ri(14),
                  color: AppTheme.mutedSteel,
                ),
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
                      ? SizedBox(
                          width: context.rw(16),
                          height: context.rh(16),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Reply'),
                ),
              ],
            ),
          ],
          if (widget.depth >= 2 && review.replies.isNotEmpty) ...[
            SizedBox(height: context.rh(8)),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                LucideIcons.messageSquare,
                size: context.ri(14),
                color: AppTheme.accent,
              ),
              label: Text(
                'Show More Replies (${review.replies.length})',
                style: TextStyle(
                  fontSize: context.rsp(12),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _ServiceReviewRepliesScreen(
                      parentReview: review,
                      serviceId: widget.serviceId,
                      onEditReview: widget.onEditReview,
                      onDeleteReview: widget.onDeleteReview,
                      onReplyTo: widget.onReplyTo,
                    ),
                  ),
                );
              },
            ),
          ] else if (widget.depth < 2 && review.replies.isNotEmpty) ...[
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
                        _ServiceReviewCard(
                          review: review.replies.first,
                          isOwn:
                              review.replies.first.reviewerId ==
                              currentUserId,
                          serviceId: widget.serviceId,
                          onEditReview: widget.onEditReview,
                          onDeleteReview: widget.onDeleteReview,
                          onReplyTo: widget.onReplyTo,
                          depth: widget.depth + 1,
                        ),
                        if (_isExpanded)
                          ...review.replies.skip(1).map(
                                (child) => _ServiceReviewCard(
                                  review: child,
                                  isOwn:
                                      child.reviewerId == currentUserId,
                                  serviceId: widget.serviceId,
                                  onEditReview: widget.onEditReview,
                                  onDeleteReview: widget.onDeleteReview,
                                  onReplyTo: widget.onReplyTo,
                                  depth: widget.depth + 1,
                                ),
                              ),
                        if (review.replies.length > 1) ...[
                          SizedBox(height: context.rh(4)),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.only(
                                left: context.rw(4),
                                top: context.rh(4),
                                bottom: context.rh(4),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              _isExpanded
                                  ? LucideIcons.chevronUp
                                  : LucideIcons.chevronDown,
                              size: context.ri(14),
                              color: AppTheme.accent,
                            ),
                            label: Text(
                              _isExpanded
                                  ? 'Collapse replies'
                                  : 'Show ${review.replies.length - 1} '
                                    'more reply(s)',
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
}

/// Full conversation thread for deeply nested service replies, mirroring
/// the product detail replies thread.
class _ServiceReviewRepliesScreen extends ConsumerWidget {
  final ServiceReview parentReview;
  final String serviceId;
  final void Function(ServiceReview review) onEditReview;
  final void Function(ServiceReview review) onDeleteReview;
  final Future<void> Function(ServiceReview parent, String text) onReplyTo;

  const _ServiceReviewRepliesScreen({
    required this.parentReview,
    required this.serviceId,
    required this.onEditReview,
    required this.onDeleteReview,
    required this.onReplyTo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
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
            _ServiceReviewCard(
              review: parentReview,
              isOwn:
                  parentReview.reviewerId ==
                  ref.read(authProvider).user?.id,
              serviceId: serviceId,
              onEditReview: onEditReview,
              onDeleteReview: onDeleteReview,
              onReplyTo: onReplyTo,
              depth: 0,
            ),
          ],
        ),
      ),
    );
  }
}

void _showReviewImage(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final y = date.year == DateTime.now().year ? '' : ' ${date.year}';
  return '${date.day} ${_monthName(date.month)}$y';
}

String _monthName(int month) {
  const names = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[month];
}

/// Bottom-sheet form: 5-tap star input + comment. Pops with true on success.
class _ServiceReviewForm extends StatefulWidget {
  final ServiceReview? existing;
  final Future<void> Function(
    int rating,
    String comment,
    List<String> keepMediaUrls,
    List<File> newImageFiles,
  ) onSubmit;

  const _ServiceReviewForm({this.existing, required this.onSubmit});

  @override
  State<_ServiceReviewForm> createState() => _ServiceReviewFormState();
}

class _ServiceReviewFormState extends State<_ServiceReviewForm> {
  static const _maxImages = 5;
  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _commentCtrl = TextEditingController(
    text: widget.existing?.comment ?? '',
  );
  late final List<String> _keepMediaUrls = [
    ...?widget.existing?.mediaUrls,
  ];
  final List<File> _newImageFiles = [];
  bool _isSubmitting = false;

  int get _totalImages => _keepMediaUrls.length + _newImageFiles.length;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImages;
    if (remaining <= 0) return;
    final source = await showShadSheet<ImageSource>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Add Photos'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      LucideIcons.camera,
                      color: AppTheme.accent,
                    ),
                    title: const Text('Camera'),
                    onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(
                      LucideIcons.image,
                      color: AppTheme.successMoss,
                    ),
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
    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() => _newImageFiles.add(File(picked.path)));
      }
    } else {
      final images = await picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (images.isNotEmpty && mounted) {
        setState(() {
          _newImageFiles.addAll(
            images.take(remaining).map((x) => File(x.path)),
          );
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please pick a star rating')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(
        _rating,
        _commentCtrl.text.trim(),
        _keepMediaUrls,
        _newImageFiles,
      );
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Thank you for your review!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ShadToaster.of(context).show(
          ShadToast(title: Text('Couldn\'t save review: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + context.rh(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: context.rh(12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Icon(
                    star <= _rating ? Icons.star : Icons.star_border,
                    size: context.ri(38),
                    color: Colors.amber,
                  ),
                ),
            ],
          ),
          SizedBox(height: context.rh(16)),
          ShadInput(
            controller: _commentCtrl,
            placeholder: const Text('Share your experience...'),
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
          SizedBox(height: context.rh(12)),
          if (_totalImages < _maxImages)
            ShadButton.ghost(
              onPressed: _pickImages,
              leading: Icon(LucideIcons.image, size: context.ri(18)),
              child: Text('Add Photos ($_totalImages/$_maxImages)'),
            )
          else
            Text(
              'Maximum $_maxImages photos attached',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
          if (_totalImages > 0) ...[
            SizedBox(height: context.rh(8)),
            SizedBox(
              height: context.rh(72),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._keepMediaUrls.map(
                    (url) => _ReviewImageThumbnail(
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                      ),
                      onRemove: () =>
                          setState(() => _keepMediaUrls.remove(url)),
                    ),
                  ),
                  ..._newImageFiles.asMap().entries.map(
                        (e) => _ReviewImageThumbnail(
                          child: Image.file(e.value, fit: BoxFit.cover),
                          onRemove: () => setState(
                            () => _newImageFiles.removeAt(e.key),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
          SizedBox(height: context.rh(16)),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Submit Review',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewImageThumbnail extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;

  const _ReviewImageThumbnail({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: context.rw(72),
          height: context.rh(72),
          margin: EdgeInsets.only(right: context.rw(8)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.rr(8)),
            color: AppTheme.warmMist,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        Positioned(
          top: context.rh(2),
          right: context.rw(10),
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: context.rAll(2),
              decoration: const BoxDecoration(
                color: AppTheme.destructive,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                size: context.ri(14),
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
