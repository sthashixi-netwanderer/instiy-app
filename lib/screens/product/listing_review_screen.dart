import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/picked_media.dart';
import '../../models/product_model.dart';
import '../../utils/media_image.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';

class ListingReviewData {
  final String title;
  final String description;
  final double price;
  final String? categoryName;
  final ProductCondition condition;
  final List<String> campuses;
  final List<Map<String, String>> specifications;
  final int stockQuantity;
  final String deliveryOption;
  final double deliveryFee;
  final Map<String, double> institutionDeliveryFees;
  final double discountPercent;
  final DateTime? discountStartDate;
  final DateTime? discountEndDate;
  final List<String> existingImageUrls;
  final List<PickedMedia> selectedImages;
  final List<String> existingVideoUrls;
  final List<dynamic> selectedVideos;
  final int thumbnailExistingIndex;
  final int thumbnailNewIndex;
  final int clipVideoExistingIndex;
  final int clipVideoNewIndex;
  final bool showOnClips;

  const ListingReviewData({
    required this.title,
    required this.description,
    required this.price,
    required this.categoryName,
    required this.condition,
    required this.campuses,
    required this.specifications,
    required this.stockQuantity,
    required this.deliveryOption,
    required this.deliveryFee,
    required this.institutionDeliveryFees,
    required this.discountPercent,
    required this.discountStartDate,
    required this.discountEndDate,
    required this.existingImageUrls,
    required this.selectedImages,
    required this.existingVideoUrls,
    required this.selectedVideos,
    required this.thumbnailExistingIndex,
    required this.thumbnailNewIndex,
    required this.clipVideoExistingIndex,
    required this.clipVideoNewIndex,
    required this.showOnClips,
  });

  int get totalImages => existingImageUrls.length + selectedImages.length;
  int get totalVideos => existingVideoUrls.length + selectedVideos.length;
}

class ListingReviewScreen extends StatefulWidget {
  final ListingReviewData data;
  final Future<void> Function() onConfirm;

  const ListingReviewScreen({
    super.key,
    required this.data,
    required this.onConfirm,
  });

  @override
  State<ListingReviewScreen> createState() => _ListingReviewScreenState();
}

class _ListingReviewScreenState extends State<ListingReviewScreen> {
  bool _isPublishing = false;

  Future<void> _confirm() async {
    if (_isPublishing) return;
    setState(() => _isPublishing = true);
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Widget _section(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.mutedSteel, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.charcoalInk,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaTile({String? url, PickedMedia? media, required bool isCover}) {
    final image = url != null
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: 112,
            height: 112,
          )
        : Image(
            image: mediaImageProvider(media!),
            fit: BoxFit.cover,
            width: 112,
            height: 112,
          );
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        if (isCover)
          Positioned(
            bottom: 5,
            left: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Cover',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mediaSection() {
    final tiles = <Widget>[];
    for (var i = 0; i < widget.data.existingImageUrls.length; i++) {
      tiles.add(
        _mediaTile(
          url: widget.data.existingImageUrls[i],
          isCover: widget.data.thumbnailExistingIndex == i,
        ),
      );
    }
    for (var i = 0; i < widget.data.selectedImages.length; i++) {
      tiles.add(
        _mediaTile(
          media: widget.data.selectedImages[i],
          isCover:
              widget.data.thumbnailExistingIndex == -1 &&
              widget.data.thumbnailNewIndex == i,
        ),
      );
    }
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => tiles[index],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final delivery = data.deliveryOption == 'pickup'
        ? 'Pickup'
        : 'Delivery (${data.deliveryFee.toStringAsFixed(2)})';
    final discount = data.discountPercent > 0
        ? '${data.discountPercent.toStringAsFixed(0)}%'
              '${data.discountStartDate != null ? ' • starts ${data.discountStartDate!.toLocal().toString().split(' ').first}' : ''}'
              '${data.discountEndDate != null ? ' • ends ${data.discountEndDate!.toLocal().toString().split(' ').first}' : ''}'
        : 'None';

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.cleanBackground,
      child: Column(
        children: [
          Padding(
            padding: context.rAll(16),
            child: Row(
              children: [
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: _isPublishing
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Review Listing',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: context.rAll(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(LucideIcons.eye, size: 18, color: AppTheme.accent),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Review all details carefully. You can go back and edit anything before publishing.',
                            style: TextStyle(
                              color: AppTheme.charcoalInk,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _section('Photos (${data.totalImages})', _mediaSection()),
                  _section(
                    'Basic information',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.description,
                          style: const TextStyle(
                            color: AppTheme.mutedSteel,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _detail('Price', data.price.toStringAsFixed(2)),
                        _detail(
                          'Category',
                          data.categoryName ?? 'Not selected',
                        ),
                        _detail('Condition', data.condition.name),
                        _detail('Stock', data.stockQuantity.toString()),
                      ],
                    ),
                  ),
                  _section(
                    'Availability & delivery',
                    Column(
                      children: [
                        _detail('Campuses', data.campuses.join(', ')),
                        _detail('Option', delivery),
                        if (data.institutionDeliveryFees.isNotEmpty)
                          _detail(
                            'Campus fees',
                            data.institutionDeliveryFees.entries
                                .map(
                                  (e) =>
                                      '${e.key}: ${e.value.toStringAsFixed(2)}',
                                )
                                .join(', '),
                          ),
                      ],
                    ),
                  ),
                  _section(
                    'Specifications',
                    Column(
                      children: data.specifications
                          .map(
                            (spec) =>
                                _detail(spec.keys.first, spec.values.first),
                          )
                          .toList(),
                    ),
                  ),
                  _section(
                    'Additional details',
                    Column(
                      children: [
                        _detail('Discount', discount),
                        _detail('Videos', '${data.totalVideos} attached'),
                        _detail(
                          'Show on Clips',
                          data.showOnClips ? 'Yes' : 'No',
                        ),
                        if (data.showOnClips && data.totalVideos > 1)
                          _detail(
                            'Clip video',
                            'Video ${(data.clipVideoExistingIndex >= 0 ? data.clipVideoExistingIndex : data.existingVideoUrls.length + data.clipVideoNewIndex) + 1}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: context.rAll(16),
              child: Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      enabled: !_isPublishing,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Edit listing'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadButton(
                      enabled: !_isPublishing,
                      onPressed: _confirm,
                      child: _isPublishing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Publish listing'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
