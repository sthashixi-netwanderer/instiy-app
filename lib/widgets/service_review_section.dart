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
      setState(() => _reviews = reviews);
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
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Delete Review'),
      description: const Text(
        'Your review will be removed permanently. This cannot be undone.',
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
      if (mounted) {
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
              onEdit: () => _openForm(existing: review),
              onDelete: () => _deleteReview(review),
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

class _ServiceReviewCard extends StatelessWidget {
  final ServiceReview review;
  final bool isOwn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceReviewCard({
    required this.review,
    required this.isOwn,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: context.rh(12)),
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(12)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
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
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= review.rating
                                ? Icons.star
                                : Icons.star_border,
                            size: context.ri(13),
                            color: Colors.amber,
                          ),
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
              if (isOwn)
                PopupMenuButton<String>(
                  icon: Icon(
                    LucideIcons.ellipsis,
                    size: context.ri(18),
                    color: AppTheme.mutedSteel,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
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
        ],
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
