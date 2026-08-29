import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/picked_media.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../providers/providers.dart';
import '../../providers/product_provider.dart';
import '../../config/app_theme.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../models/draft_listing_model.dart';
import '../../services/draft_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../services/video_service.dart';
import '../../services/ai_service.dart';
import '../../services/business_profile_service.dart';
import '../../services/watermark_service.dart';
import '../../services/sound_service.dart';
import '../../widgets/image_picker_sheet.dart';
import '../../widgets/multi_institution_picker.dart';
import '../../widgets/required_label.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';
import '../../utils/formatters.dart';
import '../../utils/media_image.dart';
import 'listing_review_screen.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  final Product? existingProduct;
  final String? source;

  const CreateListingScreen({super.key, this.existingProduct, this.source});

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  List<String> _selectedCampuses = [];
  Map<String, double> _institutionDeliveryFees = {};
  // When true the listing is published with no campus restriction — visible
  // and purchasable by buyers from any institution.
  bool _allInstitutions = false;
  bool _useSameDeliveryFee = true;
  final _stockController = TextEditingController(text: '1');
  final _deliveryFeeController = TextEditingController(text: '0.00');
  String _deliveryOption = 'pickup';
  final List<_SpecPair> _specifications = [];

  // Show on Clips
  bool _showOnClips = false;

  bool get _hasVideo =>
      _selectedVideos.isNotEmpty || _existingVideoUrls.isNotEmpty;
  int get _totalVideoCount =>
      _selectedVideos.length + _existingVideoUrls.length;
  bool get _needsClipVideoSelection => _showOnClips && _totalVideoCount >= 2;
  bool get _hasClipVideoSelected =>
      _clipVideoExistingIndex != -1 || _clipVideoNewIndex != -1;
  static const int _maxVideos = 3;
  bool get _canAddVideo => _totalVideoCount < _maxVideos;

  // Discount fields
  bool _hasDiscount = false;
  final _discountPercentController = TextEditingController();
  DateTime? _discountStartDate;
  DateTime? _discountEndDate;

  void _addSpec({String key = '', String value = ''}) {
    final keyCtrl = TextEditingController(text: key);
    final valCtrl = TextEditingController(text: value);
    keyCtrl.addListener(_onFieldChanged);
    valCtrl.addListener(_onFieldChanged);
    setState(() {
      _specifications.add(
        _SpecPair(keyController: keyCtrl, valueController: valCtrl),
      );
    });
  }

  void _removeSpec(int index) {
    final pair = _specifications[index];
    pair.keyController.removeListener(_onFieldChanged);
    pair.valueController.removeListener(_onFieldChanged);
    pair.keyController.dispose();
    pair.valueController.dispose();
    setState(() => _specifications.removeAt(index));
  }

  ProductCondition? _selectedCondition;
  String? _selectedCategoryId;
  final List<dynamic> _selectedImages = [];
  List<String> _existingImageUrls = [];
  final List<dynamic> _selectedVideos = [];
  List<String> _existingVideoUrls = [];
  final List<VideoPlayerController?> _videoPreviewControllers = [];
  bool _isUploading = false;
  bool _isAIProcessing = false;
  // Thumbnail selection: track which image the seller chose as thumbnail.
  // _thumbnailExistingIndex => index into _existingImageUrls (-1 means none)
  // _thumbnailNewIndex => index into _selectedImages (-1 means none)
  // Only one of these can be non-(-1) at a time.
  int _thumbnailExistingIndex = -1;
  int _thumbnailNewIndex = -1;
  // Clip video selection: which video appears in the Clips feed
  int _clipVideoExistingIndex = -1; // index into _existingVideoUrls
  int _clipVideoNewIndex = -1; // index into _selectedVideos
  bool get _isEditing => widget.existingProduct != null;

  // Draft state
  String? _draftId;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(productProvider).loadCategories();
    });
    if (_isEditing) {
      _populateFields();
    } else {
      _loadDraft();
    }
    // Debounced auto-save for text fields
    _titleController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _priceController.addListener(_onFieldChanged);
  }

  void _populateFields() {
    final p = widget.existingProduct!;
    _titleController.text = p.title;
    _descriptionController.text = p.description;
    _priceController.text = p.price.toString();
    if (p.campuses.isEmpty) {
      // Previously published for all institutions.
      _allInstitutions = true;
    } else {
      _selectedCampuses.addAll(p.campuses);
    }
    _selectedCondition = p.condition;
    _selectedCategoryId = p.categoryId;
    _existingImageUrls = List.from(p.imageUrls);
    _existingVideoUrls = List.from(p.videoUrls);
    // Pre-select clip video from existing product
    if (p.clipVideoUrl != null) {
      final clipIdx = _existingVideoUrls.indexOf(p.clipVideoUrl!);
      if (clipIdx != -1) _clipVideoExistingIndex = clipIdx;
    }
    // Pre-select thumbnail from existing product
    if (p.thumbnailUrl != null) {
      final idx = _existingImageUrls.indexOf(p.thumbnailUrl!);
      if (idx != -1) {
        _thumbnailExistingIndex = idx;
      }
    } else if (_existingImageUrls.isNotEmpty) {
      _thumbnailExistingIndex = 0; // default to first
    }
    _stockController.text = p.stockQuantity.toString();
    _deliveryOption = p.deliveryOption;
    _deliveryFeeController.text = p.deliveryFee.toStringAsFixed(2);
    if (p.institutionDeliveryFees.isNotEmpty) {
      _institutionDeliveryFees = Map.from(p.institutionDeliveryFees);
      final uniqueFees = _institutionDeliveryFees.values.toSet();
      _useSameDeliveryFee = uniqueFees.length == 1;
      // Sync the main fee field with the first campus fee
      if (_useSameDeliveryFee) {
        _deliveryFeeController.text = _institutionDeliveryFees.values.first
            .toStringAsFixed(2);
      }
    }
    for (final spec in p.specifications) {
      _addSpec(key: spec.keys.first, value: spec.values.first);
    }
    // Load discount data
    if (p.discountPercent > 0) {
      _hasDiscount = true;
      _discountPercentController.text = p.discountPercent.toString();
      _discountStartDate = p.discountStartDate;
      _discountEndDate = p.discountEndDate;
    }
    _showOnClips = p.showOnClips;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.removeListener(_onFieldChanged);
    _descriptionController.removeListener(_onFieldChanged);
    _priceController.removeListener(_onFieldChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _deliveryFeeController.dispose();
    _discountPercentController.dispose();
    for (final c in _videoPreviewControllers) {
      c?.dispose();
    }
    _videoPreviewControllers.clear();
    for (final s in _specifications) {
      s.keyController.removeListener(_onFieldChanged);
      s.valueController.removeListener(_onFieldChanged);
      s.keyController.dispose();
      s.valueController.dispose();
    }
    super.dispose();
  }

  Future<void> _clearAllFields() async {
    final confirmed = await AppTheme.showGlassDialog<bool>(
      context: context,
      title: const Text('Clear All Fields'),
      description: const Text(
        'This will remove all entered data including images, title, description, and pricing. This cannot be undone.',
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Clear All'),
        ),
      ],
    );

    if (confirmed != true) return;

    _debounce?.cancel();
    setState(() {
      _titleController.clear();
      _descriptionController.clear();
      _priceController.clear();
      _stockController.text = '1';
      _deliveryFeeController.text = '0.00';
      _discountPercentController.clear();
      _selectedCategoryId = null;
      _selectedCondition = null;
      _selectedCampuses = [];
      _institutionDeliveryFees = {};
      _allInstitutions = false;
      _useSameDeliveryFee = true;
      _deliveryOption = 'pickup';
      _selectedImages.clear();
      _existingImageUrls = [];
      _selectedVideos.clear();
      _existingVideoUrls = [];
      _thumbnailExistingIndex = -1;
      _thumbnailNewIndex = -1;
      _hasDiscount = false;
      _discountStartDate = null;
      _discountEndDate = null;
      _showOnClips = false;
      _clipVideoExistingIndex = -1;
      _clipVideoNewIndex = -1;
      _videoPreviewControllers.clear();
      _videoPreviewControllers.addAll(
        List.filled(_existingVideoUrls.length, null),
      );
      for (final s in _specifications) {
        s.keyController.removeListener(_onFieldChanged);
        s.valueController.removeListener(_onFieldChanged);
        s.keyController.dispose();
        s.valueController.dispose();
      }
      _specifications.clear();
      _isUploading = false;
      _isAIProcessing = false;
      _draftId = null;
    });
    DraftService.clearDraft(); // ignore: unawaited_futures
  }

  void _onFieldChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), _saveDraft);
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isFormValid {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final priceStr = _priceController.text.trim();
    final hasImages =
        _existingImageUrls.isNotEmpty || _selectedImages.isNotEmpty;
    final specCount = _specifications
        .where((s) => s.keyController.text.trim().isNotEmpty)
        .length;
    final hasCampuses = _selectedCampuses.isNotEmpty || _allInstitutions;
    return title.isNotEmpty &&
        description.isNotEmpty &&
        priceStr.isNotEmpty &&
        _selectedCondition != null &&
        hasImages &&
        specCount >= 3 &&
        hasCampuses &&
        (!_needsClipVideoSelection || _hasClipVideoSelected);
  }

  Future<void> _loadDraft() async {
    final draft = await DraftService.loadDraft();
    if (draft == null || !mounted) return;

    // Don't load publishing drafts — they're in-flight
    if (draft.status == DraftStatus.publishing) return;

    // Load both draft and failed drafts so users can retry
    setState(() {
      _draftId = draft.id;
      _titleController.text = draft.title;
      _descriptionController.text = draft.description;
      _priceController.text = draft.price > 0
          ? draft.price.toStringAsFixed(2)
          : '';
      _selectedCategoryId = draft.categoryId;
      _selectedCondition = draft.condition;
      _selectedCampuses = List.from(draft.campuses);
      _stockController.text = draft.stockQuantity.toString();
      _deliveryOption = draft.deliveryOption;
      _deliveryFeeController.text = draft.deliveryFee.toStringAsFixed(2);
      _institutionDeliveryFees = Map.from(draft.institutionDeliveryFees);
      _useSameDeliveryFee = _institutionDeliveryFees.values.toSet().length <= 1;
      _hasDiscount = draft.discountPercent > 0;
      _discountPercentController.text = draft.discountPercent > 0
          ? draft.discountPercent.toString()
          : '';
      _discountStartDate = draft.discountStartDate;
      _discountEndDate = draft.discountEndDate;

      // Load images from local paths (mobile only — web has no local filesystem)
      _selectedImages.clear();
      if (!kIsWeb) {
        // On mobile, files may exist locally from a previous session.
        // We skip loading them on web since there's no local filesystem.
      }
      if (_selectedImages.isNotEmpty) {
        _thumbnailNewIndex = draft.thumbnailIndex.clamp(
          0,
          _selectedImages.length - 1,
        );
      }

      // Load videos from local paths (mobile only)
      _selectedVideos.clear();
      if (!kIsWeb) {
        // On mobile, files may exist locally from a previous session.
      }

      // Load specifications
      _specifications.clear();
      for (final spec in draft.specifications) {
        _addSpec(
          key: spec.keys.isNotEmpty ? spec.keys.first : '',
          value: spec.values.isNotEmpty ? spec.values.first : '',
        );
      }
    });
  }

  ListingReviewData _buildReviewData(ProductProvider productProv) {
    Category? category;
    for (final candidate in productProv.categories) {
      if (candidate.id == _selectedCategoryId) {
        category = candidate;
        break;
      }
    }

    return ListingReviewData(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      categoryName: category?.name,
      condition: _selectedCondition!,
      campuses: List<String>.from(_selectedCampuses),
      specifications: _specifications
          .where((s) => s.keyController.text.trim().isNotEmpty)
          .map(
            (s) => {s.keyController.text.trim(): s.valueController.text.trim()},
          )
          .toList(),
      stockQuantity: int.tryParse(_stockController.text.trim()) ?? 1,
      deliveryOption: _deliveryOption,
      deliveryFee: _deliveryOption == 'pickup'
          ? 0
          : (double.tryParse(_deliveryFeeController.text.trim()) ?? 0),
      institutionDeliveryFees: Map<String, double>.from(
        _institutionDeliveryFees,
      ),
      discountPercent: _hasDiscount
          ? (double.tryParse(_discountPercentController.text.trim()) ?? 0)
          : 0,
      discountStartDate: _hasDiscount ? _discountStartDate : null,
      discountEndDate: _hasDiscount ? _discountEndDate : null,
      existingImageUrls: List<String>.from(_existingImageUrls),
      selectedImages: _selectedImages.whereType<PickedMedia>().toList(),
      existingVideoUrls: List<String>.from(_existingVideoUrls),
      selectedVideos: List<dynamic>.from(_selectedVideos),
      thumbnailExistingIndex: _thumbnailExistingIndex,
      thumbnailNewIndex: _thumbnailNewIndex,
      clipVideoExistingIndex: _clipVideoExistingIndex,
      clipVideoNewIndex: _clipVideoNewIndex,
      showOnClips: _showOnClips,
    );
  }

  Future<void> _saveDraft() async {
    if (_isEditing) return; // Don't save drafts when editing existing products

    final draft = DraftListing(
      id: _draftId ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      categoryId: _selectedCategoryId,
      imagePaths: _selectedImages
          .map<String>((f) => f is PickedMedia ? f.name : f.path ?? f.name)
          .toList(),
      videoPaths: _selectedVideos
          .map<String>((f) => f is PickedMedia ? f.name : f.path ?? f.name)
          .toList(),
      thumbnailIndex: _thumbnailNewIndex >= 0 ? _thumbnailNewIndex : 0,
      condition: _selectedCondition,
      campuses: _selectedCampuses,
      specifications: _specifications
          .where((s) => s.keyController.text.trim().isNotEmpty)
          .map(
            (s) => {s.keyController.text.trim(): s.valueController.text.trim()},
          )
          .toList(),
      stockQuantity: int.tryParse(_stockController.text.trim()) ?? 1,
      deliveryOption: _deliveryOption,
      deliveryFee: double.tryParse(_deliveryFeeController.text.trim()) ?? 0,
      institutionDeliveryFees: _institutionDeliveryFees,
      discountPercent: _hasDiscount
          ? (double.tryParse(_discountPercentController.text.trim()) ?? 0)
          : 0,
      discountStartDate: _hasDiscount ? _discountStartDate : null,
      discountEndDate: _hasDiscount ? _discountEndDate : null,
      status: DraftStatus.draft,
      savedAt: DateTime.now(),
    );

    _draftId = draft.id;
    await DraftService.saveDraft(draft);
  }

  Future<void> _pickImages() async {
    final images = await ImagePickerSheet.pickMultiple(context);
    if (images.isNotEmpty) {
      setState(() {
        final prevTotal = _existingImageUrls.length + _selectedImages.length;
        _selectedImages.addAll(images);
        // If no thumbnail is selected yet, auto-select the first newly added image
        if (_thumbnailExistingIndex == -1 && _thumbnailNewIndex == -1) {
          if (_existingImageUrls.isEmpty) {
            _thumbnailNewIndex = 0; // first new image
          }
        }
        // If existing images are empty and no new thumbnail selected yet, pick first new
        if (prevTotal == 0 &&
            _thumbnailExistingIndex == -1 &&
            _thumbnailNewIndex == -1) {
          _thumbnailNewIndex = 0;
        }
      });
      _saveDraft(); // ignore: unawaited_futures
    }
  }

  Future<void> _pickVideo() async {
    if (_totalVideoCount >= _maxVideos) return;
    final video = await VideoService.pickVideo(context);
    if (video != null) {
      setState(() {
        _selectedVideos.add(video);
        _videoPreviewControllers.add(null);
      });
      _initVideoPreview(_selectedVideos.length - 1);
      _saveDraft(); // ignore: unawaited_futures
    }
  }

  void _initVideoPreview(int index) {
    if (index < 0 || index >= _selectedVideos.length) return;
    _videoPreviewControllers[index]?.dispose();
    final videoItem = _selectedVideos[index];
    final controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse('about:blank'))
        : VideoPlayerController.file(videoItem);
    controller.initialize().then((_) {
      if (mounted) setState(() {});
      controller.play();
    });
    _videoPreviewControllers[index] = controller;
  }

  void _removeVideo(int index) {
    setState(() {
      if (index < _selectedVideos.length) {
        // Removing a newly-added video file — adjust clip selection index
        if (_clipVideoNewIndex == index) {
          _clipVideoNewIndex = -1;
        } else if (_clipVideoNewIndex > index) {
          _clipVideoNewIndex--;
        }
        _selectedVideos.removeAt(index);
      } else {
        // Removing an existing video URL — adjust clip selection index
        final existingIdx = index - _selectedVideos.length;
        if (_clipVideoExistingIndex == existingIdx) {
          _clipVideoExistingIndex = -1;
        } else if (_clipVideoExistingIndex > existingIdx) {
          _clipVideoExistingIndex--;
        }
        _existingVideoUrls.removeAt(existingIdx);
      }
      if (index < _selectedVideos.length) {
        _videoPreviewControllers[index]?.dispose();
        _videoPreviewControllers.removeAt(index);
      } else {
        final existingIdx = index - _selectedVideos.length;
        _videoPreviewControllers.removeAt(existingIdx);
      }
    });
    _saveDraft();
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      // Adjust thumbnail index
      if (_thumbnailNewIndex == index) {
        // The thumbnail image was removed — fall back
        _thumbnailNewIndex = -1;
        if (_selectedImages.isNotEmpty) {
          _thumbnailNewIndex = 0;
        } else if (_existingImageUrls.isNotEmpty) {
          _thumbnailExistingIndex = 0;
        }
      } else if (_thumbnailNewIndex > index) {
        _thumbnailNewIndex--;
      }
    });
    _saveDraft();
  }

  Future<void> _handleSubmit({bool fromReview = false}) async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCondition == null) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Please select the condition of the product'),
        ),
      );
      return;
    }

    if (_existingImageUrls.isEmpty && _selectedImages.isEmpty) {
      ShadToaster.of(
        context,
      ).show(const ShadToast(title: Text('Please add at least one image')));
      return;
    }

    final validSpecs = _specifications
        .where((s) => s.keyController.text.trim().isNotEmpty)
        .toList();

    if (validSpecs.length < 3) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please add at least 3 specifications')),
      );
      return;
    }

    if (_selectedCampuses.isEmpty && !_allInstitutions) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text(
            'Please select at least one campus/location or All Institutions',
          ),
        ),
      );
      return;
    }

    if (_showOnClips && _totalVideoCount >= 2 && !_hasClipVideoSelected) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Choose a clip video'),
          description: Text(
            'Please select which video to show in the Clips feed.',
          ),
        ),
      );
      return;
    }

    if (!_isEditing && !fromReview) {
      await _saveDraft();
      if (!mounted) return;
      final productProv = ref.read(productProvider);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingReviewScreen(
            data: _buildReviewData(productProv),
            onConfirm: () => _handleSubmit(fromReview: true),
          ),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    final provider = ref.read(productProvider);

    // Fetch business name for watermark (falls back to the seller's name)
    String? storeName;
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId != null) {
        final profile = await BusinessProfileService.getProfile(userId);
        storeName = profile?.businessName;
        storeName ??= SupabaseService.instance.currentUser?.userMetadata?['full_name'] as String?;
      }
    } catch (_) {}

    // Capture ALL values from text controllers and state lists/variables BEFORE popping/disposing
    final titleVal = _titleController.text.trim();
    final descriptionVal = _descriptionController.text.trim();
    final priceVal = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final categoryIdVal = _selectedCategoryId;
    final conditionVal = _selectedCondition!;
    final campusesVal = _selectedCampuses.isEmpty
        ? null
        : List<String>.from(_selectedCampuses);
    final deliveryOptionVal = _deliveryOption;

    final selectedImagesCopy = List<dynamic>.from(_selectedImages);
    final selectedVideosCopy = List<dynamic>.from(_selectedVideos);
    final existingImageUrlsCopy = List<String>.from(_existingImageUrls);
    final existingVideoUrlsCopy = List<String>.from(_existingVideoUrls);

    final thumbnailExistingIdx = _thumbnailExistingIndex;
    final thumbnailNewIdx = _thumbnailNewIndex;
    final clipVideoExistingIdx = _clipVideoExistingIndex;
    final clipVideoNewIdx = _clipVideoNewIndex;

    final specs = validSpecs
        .map(
          (s) => {s.keyController.text.trim(): s.valueController.text.trim()},
        )
        .toList();
    final stockVal = int.tryParse(_stockController.text.trim()) ?? 1;
    final deliveryFeeVal = _deliveryOption == 'pickup'
        ? 0.0
        : (double.tryParse(_deliveryFeeController.text.trim()) ?? 0.00);
    final instFees = _deliveryOption != 'pickup' && _selectedCampuses.isNotEmpty
        ? (_useSameDeliveryFee
              ? {for (final c in _selectedCampuses) c: deliveryFeeVal}
              : _institutionDeliveryFees)
        : <String, double>{};
    final discountPercentVal = _hasDiscount
        ? (double.tryParse(_discountPercentController.text.trim()) ?? 0.0)
        : 0.0;
    final discountStartVal = _hasDiscount && _discountStartDate != null
        ? DateFormat('yyyy-MM-dd').format(_discountStartDate!)
        : null;
    final discountEndVal = _hasDiscount && _discountEndDate != null
        ? DateFormat('yyyy-MM-dd').format(_discountEndDate!)
        : null;

    if (_isEditing) {
      try {
        List<String> imageUrls = List.from(existingImageUrlsCopy);
        List<String> videoUrls = List.from(existingVideoUrlsCopy);

        if (selectedImagesCopy.isNotEmpty) {
          final newUrls = <String>[];
          for (var image in selectedImagesCopy) {
            // Burn the watermark into newly added images before upload.
            if (image is PickedMedia) {
              image = await WatermarkService.addWatermark(
                media: image,
                storeName: storeName,
              );
            }
            final url = await StorageService.uploadImage(
              file: image,
              folder: 'products',
            );
            newUrls.add(url);
          }
          imageUrls.addAll(newUrls);
        }

        if (selectedVideosCopy.isNotEmpty) {
          for (var video in selectedVideosCopy) {
            // Compress video for optimal playback
            video = await VideoService.compressVideo(video);
            final url = await StorageService.uploadFile(
              file: video,
              folder: 'products/videos',
              contentType: 'video/mp4',
              extension: 'mp4',
            );
            videoUrls.add(url);
          }
        }

        String? thumbnailUrl;
        if (thumbnailExistingIdx != -1 &&
            thumbnailExistingIdx < existingImageUrlsCopy.length) {
          thumbnailUrl = existingImageUrlsCopy[thumbnailExistingIdx];
        } else if (thumbnailNewIdx != -1 &&
            thumbnailNewIdx < selectedImagesCopy.length) {
          final uploadedIndex = existingImageUrlsCopy.length + thumbnailNewIdx;
          if (uploadedIndex < imageUrls.length) {
            thumbnailUrl = imageUrls[uploadedIndex];
          }
        }
        thumbnailUrl ??= imageUrls.isNotEmpty ? imageUrls.first : null;

        // Resolve the clip video URL
        String? clipVideoUrlVal;
        if (_showOnClips) {
          final totalVids =
              existingVideoUrlsCopy.length + selectedVideosCopy.length;
          if (totalVids <= 1) {
            clipVideoUrlVal = videoUrls.isNotEmpty ? videoUrls.first : null;
          } else if (clipVideoExistingIdx != -1 &&
              clipVideoExistingIdx < existingVideoUrlsCopy.length) {
            clipVideoUrlVal = existingVideoUrlsCopy[clipVideoExistingIdx];
          } else if (clipVideoNewIdx != -1) {
            final uploadedIdx = existingVideoUrlsCopy.length + clipVideoNewIdx;
            if (uploadedIdx < videoUrls.length) {
              clipVideoUrlVal = videoUrls[uploadedIdx];
            }
          }
        }

        final success = await provider.updateProduct(
          productId: widget.existingProduct!.id,
          title: titleVal,
          description: descriptionVal,
          price: priceVal,
          categoryId: categoryIdVal,
          imageUrls: imageUrls,
          videoUrls: videoUrls,
          condition: conditionVal,
          campuses: campusesVal,
          specifications: specs,
          stockQuantity: stockVal,
          deliveryOption: deliveryOptionVal,
          deliveryFee: deliveryFeeVal,
          institutionDeliveryFees: instFees,
          discountPercent: discountPercentVal,
          discountStartDate: discountStartVal,
          discountEndDate: discountEndVal,
          thumbnailUrl: thumbnailUrl,
          showOnClips: _showOnClips,
          clipVideoUrl: clipVideoUrlVal,
        );

        if (success && mounted) {
          Navigator.of(context).pop(true);
          ShadToaster.of(
            context,
          ).show(const ShadToast(title: Text('Listing updated successfully!')));
          SoundService.playProductListedSound(); // ignore: unawaited_futures
        }
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(ShadToast(title: Text('Error: $e')));
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    } else {
      // New product — save draft as publishing, then fire-and-forget
      final publishingDraft = DraftListing(
        id: _draftId ?? const Uuid().v4(),
        title: titleVal,
        description: descriptionVal,
        price: priceVal,
        categoryId: categoryIdVal,
        imagePaths: selectedImagesCopy
            .map<String>((f) => f is PickedMedia ? f.name : f.path ?? f.name)
            .toList(),
        videoPaths: selectedVideosCopy
            .map<String>((f) => f is PickedMedia ? f.name : f.path ?? f.name)
            .toList(),
        thumbnailIndex: thumbnailNewIdx >= 0 ? thumbnailNewIdx : 0,
        condition: conditionVal,
        campuses: campusesVal ?? [],
        specifications: specs,
        stockQuantity: stockVal,
        deliveryOption: deliveryOptionVal,
        deliveryFee: deliveryFeeVal,
        institutionDeliveryFees: instFees,
        discountPercent: discountPercentVal,
        status: DraftStatus.publishing,
        savedAt: DateTime.now(),
      );
      await DraftService.saveDraft(publishingDraft);
      provider.updatePublishingDraft(publishingDraft, progress: 0);

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Your listing is being published...')),
        );
        Navigator.of(context).pop();
      }

      // Background publish — no widget dependency
      // ignore: unawaited_futures
      _publishInBackground(
        provider: provider,
        draft: publishingDraft,
        titleVal: titleVal,
        descriptionVal: descriptionVal,
        priceVal: priceVal,
        categoryIdVal: categoryIdVal,
        conditionVal: conditionVal,
        campusesVal: campusesVal,
        deliveryOptionVal: deliveryOptionVal,
        selectedImagesCopy: selectedImagesCopy,
        selectedVideosCopy: selectedVideosCopy,
        existingImageUrlsCopy: existingImageUrlsCopy,
        existingVideoUrlsCopy: existingVideoUrlsCopy,
        thumbnailExistingIdx: thumbnailExistingIdx,
        thumbnailNewIdx: thumbnailNewIdx,
        clipVideoExistingIdx: clipVideoExistingIdx,
        clipVideoNewIdx: clipVideoNewIdx,
        specs: specs,
        stockVal: stockVal,
        deliveryFeeVal: deliveryFeeVal,
        instFees: instFees,
        discountPercentVal: discountPercentVal,
        discountStartVal: discountStartVal,
        discountEndVal: discountEndVal,
        storeName: storeName,
        showOnClips: _showOnClips,
      );
    }
  }

  static Future<void> _publishInBackground({
    required ProductProvider provider,
    required DraftListing draft,
    required String titleVal,
    required String descriptionVal,
    required double priceVal,
    required String? categoryIdVal,
    required ProductCondition conditionVal,
    required List<String>? campusesVal,
    required String deliveryOptionVal,
    required List<dynamic> selectedImagesCopy,
    required List<dynamic> selectedVideosCopy,
    required List<String> existingImageUrlsCopy,
    required List<String> existingVideoUrlsCopy,
    required int thumbnailExistingIdx,
    required int thumbnailNewIdx,
    required int clipVideoExistingIdx,
    required int clipVideoNewIdx,
    required List<Map<String, String>> specs,
    required int stockVal,
    required double deliveryFeeVal,
    required Map<String, double> instFees,
    required double discountPercentVal,
    required String? discountStartVal,
    required String? discountEndVal,
    String? storeName,
    bool showOnClips = false,
  }) async {
    try {
      List<String> imageUrls = List.from(existingImageUrlsCopy);
      List<String> videoUrls = List.from(existingVideoUrlsCopy);

      final totalFiles = selectedImagesCopy.length + selectedVideosCopy.length;
      int uploadedCount = 0;

      if (selectedImagesCopy.isNotEmpty) {
        for (var image in selectedImagesCopy) {
          // Burn the watermark into newly added images before upload.
          if (image is PickedMedia) {
            image = await WatermarkService.addWatermark(
              media: image,
              storeName: storeName,
            );
          }
          final url = await StorageService.uploadImage(
            file: image,
            folder: 'products',
          );
          imageUrls.add(url);
          uploadedCount++;
          final progress = totalFiles > 0 ? uploadedCount / totalFiles : 0.5;
          final updatedDraft = draft.copyWith(
            status: DraftStatus.publishing,
            progress: progress,
          );
          await DraftService.saveDraft(updatedDraft);
          provider.updatePublishingDraft(updatedDraft, progress: progress);
        }
      }

      if (selectedVideosCopy.isNotEmpty) {
        for (var video in selectedVideosCopy) {
          // Compress video for optimal playback
          video = await VideoService.compressVideo(video);
          final url = await StorageService.uploadFile(
            file: video,
            folder: 'products/videos',
            contentType: 'video/mp4',
            extension: 'mp4',
          );
          videoUrls.add(url);
          uploadedCount++;
          final progress = totalFiles > 0 ? uploadedCount / totalFiles : 0.8;
          final updatedDraft = draft.copyWith(
            status: DraftStatus.publishing,
            progress: progress,
          );
          await DraftService.saveDraft(updatedDraft);
          provider.updatePublishingDraft(updatedDraft, progress: progress);
        }
      }

      String? thumbnailUrl;
      if (thumbnailExistingIdx != -1 &&
          thumbnailExistingIdx < existingImageUrlsCopy.length) {
        thumbnailUrl = existingImageUrlsCopy[thumbnailExistingIdx];
      } else if (thumbnailNewIdx != -1 &&
          thumbnailNewIdx < selectedImagesCopy.length) {
        final uploadedIndex = existingImageUrlsCopy.length + thumbnailNewIdx;
        if (uploadedIndex < imageUrls.length) {
          thumbnailUrl = imageUrls[uploadedIndex];
        }
      }
      thumbnailUrl ??= imageUrls.isNotEmpty ? imageUrls.first : null;

      // Resolve the clip video URL
      String? clipVideoUrlVal;
      if (showOnClips) {
        final totalVids =
            existingVideoUrlsCopy.length + selectedVideosCopy.length;
        if (totalVids <= 1) {
          clipVideoUrlVal = videoUrls.isNotEmpty ? videoUrls.first : null;
        } else if (clipVideoExistingIdx != -1 &&
            clipVideoExistingIdx < existingVideoUrlsCopy.length) {
          clipVideoUrlVal = existingVideoUrlsCopy[clipVideoExistingIdx];
        } else if (clipVideoNewIdx != -1) {
          final uploadedIdx = existingVideoUrlsCopy.length + clipVideoNewIdx;
          if (uploadedIdx < videoUrls.length) {
            clipVideoUrlVal = videoUrls[uploadedIdx];
          }
        }
      }

      await provider.createProduct(
        title: titleVal,
        description: descriptionVal,
        price: priceVal,
        categoryId: categoryIdVal,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        condition: conditionVal,
        campuses: campusesVal,
        specifications: specs,
        stockQuantity: stockVal,
        deliveryOption: deliveryOptionVal,
        deliveryFee: deliveryFeeVal,
        institutionDeliveryFees: instFees,
        discountPercent: discountPercentVal,
        discountStartDate: discountStartVal,
        discountEndDate: discountEndVal,
        thumbnailUrl: thumbnailUrl,
        showOnClips: showOnClips,
        clipVideoUrl: clipVideoUrlVal,
      );

      // Success — clear draft and refresh listings
      await DraftService.clearDraft();
      provider.updatePublishingDraft(null, progress: 1);
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId != null) {
        await provider.loadUserListings(userId);
      }
      SoundService.playProductListedSound(); // ignore: unawaited_futures
    } catch (e) {
      debugPrint('Background publish error: $e');
      // Mark draft as failed
      final failedDraft = draft.copyWith(
        status: DraftStatus.failed,
        errorMessage: e.toString(),
      );
      await DraftService.saveDraft(failedDraft);
      provider.updatePublishingDraft(failedDraft);
      // Refresh listings so dashboard shows the failed draft
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId != null) {
        await provider.loadUserListings(userId);
      }
    }
  }

  Future<void> _autoFillWithAI() async {
    final hasLocalImage = _selectedImages.isNotEmpty;
    final hasRemoteImage = _existingImageUrls.isNotEmpty;

    if (!hasLocalImage && !hasRemoteImage) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('No image selected'),
          description: Text(
            'Please select or upload at least one image first so the AI can analyze your product.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isAIProcessing = true;
    });

    try {
      final productProv = ref.read(productProvider);

      final result = await AIService.analyzeProductImage(
        localFiles: _selectedImages,
        imageUrls: _existingImageUrls,
        categoryNames: productProv.categories.map((c) => c.name).toList(),
      );

      if (result == null) {
        throw Exception('AI returned no response.');
      }

      setState(() {
        // Always update title and description when the user explicitly
        // taps "Auto-fill with AI" — they expect the AI to generate these.
        if (result.title.isNotEmpty) {
          _titleController.text = result.title;
        }

        if (result.description.isNotEmpty) {
          _descriptionController.text = result.description;
        }

        if (_selectedCategoryId == null) {
          Category? matchedCategory;
          final catName = result.categoryName.trim().toLowerCase();
          for (final cat in productProv.categories) {
            if (cat.name.toLowerCase() == catName) {
              matchedCategory = cat;
              break;
            }
          }

          if (matchedCategory == null && result.categoryKeyword.isNotEmpty) {
            final keyword = result.categoryKeyword.trim().toLowerCase();
            for (final cat in productProv.categories) {
              if (cat.name.toLowerCase().contains(keyword) ||
                  (cat.slug != null &&
                      cat.slug!.toLowerCase().contains(keyword))) {
                matchedCategory = cat;
                break;
              }
            }
          }

          if (matchedCategory == null && result.categoryKeyword.isNotEmpty) {
            final keyword = result.categoryKeyword.trim().toLowerCase();
            for (final cat in productProv.categories) {
              if (keyword.contains(cat.name.toLowerCase())) {
                matchedCategory = cat;
                break;
              }
            }
          }

          if (matchedCategory != null) {
            _selectedCategoryId = matchedCategory.id;
          }
        }

        final existingKeys = _specifications
            .where((s) => s.keyController.text.trim().isNotEmpty)
            .map((s) => s.keyController.text.trim().toLowerCase())
            .toSet();

        result.specifications.forEach((key, value) {
          if (!existingKeys.contains(key.toLowerCase())) {
            _SpecPair? emptyPair;
            for (final pair in _specifications) {
              if (pair.keyController.text.trim().isEmpty &&
                  pair.valueController.text.trim().isEmpty) {
                emptyPair = pair;
                break;
              }
            }

            if (emptyPair != null) {
              emptyPair.keyController.text = key;
              emptyPair.valueController.text = value;
            } else {
              _addSpec(key: key, value: value);
            }
            existingKeys.add(key.toLowerCase());
          }
        });
      });

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Auto-filled successfully!'),
            description: Text(
              'Product title, description, category, and specifications have been auto-filled by AI.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('AI Auto-fill failed'),
            description: Text(e.toString().replaceAll('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAIProcessing = false;
        });
      }
    }
  }

  Widget _buildClipVideoSelector(BuildContext context) {
    final totalCount = _selectedVideos.length + _existingVideoUrls.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: context.rh(10)),
        Row(
          children: [
            Icon(
              LucideIcons.video,
              size: context.ri(14),
              color: AppTheme.accent,
            ),
            SizedBox(width: context.rw(6)),
            RequiredLabel(
              'Choose video for Clips',
              style: TextStyle(
                fontSize: context.rsp(13),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ],
        ),
        SizedBox(height: context.rh(4)),
        Text(
          'Tap a video to select it for the Clips feed',
          style: TextStyle(
            fontSize: context.rsp(11),
            color: AppTheme.mutedSteel,
          ),
        ),
        SizedBox(height: context.rh(8)),
        SizedBox(
          height: context.rh(88),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: totalCount,
            itemBuilder: (context, i) {
              final isNew = i < _selectedVideos.length;
              final localIdx = isNew ? i : i - _selectedVideos.length;
              final isSelected = isNew
                  ? _clipVideoNewIndex == localIdx
                  : _clipVideoExistingIndex == localIdx;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isNew) {
                      _clipVideoNewIndex = localIdx;
                      _clipVideoExistingIndex = -1;
                    } else {
                      _clipVideoExistingIndex = localIdx;
                      _clipVideoNewIndex = -1;
                    }
                  });
                },
                child: Container(
                  margin: EdgeInsets.only(right: context.rw(8)),
                  width: context.rw(80),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(context.rr(10)),
                    border: Border.all(
                      color: isSelected ? AppTheme.accent : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        LucideIcons.play,
                        color: Colors.white54,
                        size: context.ri(22),
                      ),
                      if (isSelected)
                        Positioned(
                          top: context.rh(4),
                          right: context.rw(4),
                          child: Container(
                            padding: context.rAll(2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.check,
                              size: context.ri(10),
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: context.rh(5),
                        child: Text(
                          'Vid ${i + 1}',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: context.rsp(9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProv = ref.watch(productProvider);

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.cleanBackground,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            Padding(
              padding: context.rAll(16),
              child: Row(
                children: [
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: context.rw(8)),
                  Text(
                    _isEditing ? 'Edit Listing' : 'Create Listing',
                    style: TextStyle(
                      fontSize: context.rsp(18),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const Spacer(),
                  if (!_isEditing)
                    ShadButton.ghost(
                      onPressed: _clearAllFields,
                      child: const Text('Clear'),
                    ),
                  ShadButton(
                    enabled: _isFormValid,
                    onPressed: (_isUploading || !_isFormValid)
                        ? null
                        : _handleSubmit,
                    child: _isUploading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEditing ? 'Save' : 'Publish'),
                  ),
                ],
              ),
            ),

            // Dashboard source banner
            if (widget.source == 'dashboard' && !_isEditing)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.store,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Adding product to your store',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.source == 'dashboard' && !_isEditing)
              const SizedBox(height: 12),

            // Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: context.rAll(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Images Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RequiredLabel(
                          'Photos',
                          style: TextStyle(
                            fontSize: context.rsp(14),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        if (_existingImageUrls.isNotEmpty ||
                            _selectedImages.isNotEmpty)
                          Flexible(
                            child: Padding(
                              padding: EdgeInsets.only(left: context.rw(8)),
                              child: Text(
                                'Tap image to set thumbnail',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: context.rsp(11),
                                  color: AppTheme.mutedSteel,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: context.rh(8)),
                    SizedBox(
                      height: context.rh(130),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // Add Image Button
                          GestureDetector(
                            onTap: _pickImages,
                            child: Container(
                              width: context.rw(120),
                              height: context.rh(120),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(
                                  context.rr(12),
                                ),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.camera,
                                    size: context.ri(32),
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  SizedBox(height: context.rh(4)),
                                  Text(
                                    'Add Photo',
                                    style: TextStyle(
                                      color: const Color(0xFF94A3B8),
                                      fontSize: context.rsp(12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Existing Images
                          ..._existingImageUrls.asMap().entries.map((entry) {
                            final isThumbnail =
                                _thumbnailExistingIndex == entry.key;
                            return Padding(
                              padding: EdgeInsets.only(left: context.rw(8)),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _thumbnailExistingIndex = entry.key;
                                    _thumbnailNewIndex = -1;
                                  });
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Image with border highlight when thumbnail
                                    Container(
                                      width: context.rw(120),
                                      height: context.rh(120),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          context.rr(12),
                                        ),
                                        border: Border.all(
                                          color: isThumbnail
                                              ? AppTheme.accent
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          context.rr(10),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: entry.value,
                                          width: context.rw(120),
                                          height: context.rh(120),
                                          fit: BoxFit.cover,
                                          memCacheWidth: 120,
                                          placeholder: (_, _) => Container(
                                            color: AppTheme.warmMist,
                                          ),
                                          errorWidget: (_, _, _) => Container(
                                            color: AppTheme.warmMist,
                                            child: const Icon(
                                              LucideIcons.image,
                                              color: AppTheme.mutedSteel,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Thumbnail star badge
                                    if (isThumbnail)
                                      Positioned(
                                        bottom: context.rh(4),
                                        left: context.rw(4),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: context.rw(6),
                                            vertical: context.rh(3),
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accent,
                                            borderRadius: BorderRadius.circular(
                                              context.rr(8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                LucideIcons.star,
                                                size: context.ri(10),
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: context.rw(3)),
                                              Text(
                                                'Cover',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: context.rsp(9),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    // Remove button
                                    Positioned(
                                      top: context.rh(4),
                                      right: context.rw(4),
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            final removedIdx = entry.key;
                                            _existingImageUrls.removeAt(
                                              removedIdx,
                                            );
                                            // Adjust thumbnail index
                                            if (_thumbnailExistingIndex ==
                                                removedIdx) {
                                              _thumbnailExistingIndex = -1;
                                              if (_existingImageUrls
                                                  .isNotEmpty) {
                                                _thumbnailExistingIndex = 0;
                                              } else if (_selectedImages
                                                  .isNotEmpty) {
                                                _thumbnailNewIndex = 0;
                                              }
                                            } else if (_thumbnailExistingIndex >
                                                removedIdx) {
                                              _thumbnailExistingIndex--;
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: context.rAll(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
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
                                ),
                              ),
                            );
                          }),

                          // Selected (new local) Images
                          ..._selectedImages.asMap().entries.map((entry) {
                            final isThumbnail = _thumbnailNewIndex == entry.key;
                            return Padding(
                              padding: EdgeInsets.only(left: context.rw(8)),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _thumbnailNewIndex = entry.key;
                                    _thumbnailExistingIndex = -1;
                                  });
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Image with border highlight when thumbnail
                                    Container(
                                      width: context.rw(120),
                                      height: context.rh(120),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          context.rr(12),
                                        ),
                                        border: Border.all(
                                          color: isThumbnail
                                              ? AppTheme.accent
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          context.rr(10),
                                        ),
                                        child: Image(
                                          image: mediaImageProvider(
                                            entry.value,
                                          ),
                                          width: context.rw(120),
                                          height: context.rh(120),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    // Thumbnail star badge
                                    if (isThumbnail)
                                      Positioned(
                                        bottom: context.rh(4),
                                        left: context.rw(4),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: context.rw(6),
                                            vertical: context.rh(3),
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accent,
                                            borderRadius: BorderRadius.circular(
                                              context.rr(8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                LucideIcons.star,
                                                size: context.ri(10),
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: context.rw(3)),
                                              Text(
                                                'Cover',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    // Remove button
                                    Positioned(
                                      top: context.rh(4),
                                      right: context.rw(4),
                                      child: GestureDetector(
                                        onTap: () => _removeImage(entry.key),
                                        child: Container(
                                          padding: context.rAll(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
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
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    SizedBox(height: context.rh(24)),

                    // Video Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.video,
                                size: context.ri(16),
                                color: AppTheme.accent,
                              ),
                              SizedBox(width: context.rw(6)),
                              Expanded(
                                child: Text(
                                  'Product Video (Optional)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: context.rsp(14),
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedVideos.isEmpty &&
                            _existingVideoUrls.isEmpty &&
                            _canAddVideo)
                          ShadButton.ghost(
                            onPressed: _pickVideo,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.plus, size: context.ri(16)),
                                SizedBox(width: context.rw(4)),
                                const Text('Add Video'),
                              ],
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: context.rh(4)),
                    Text(
                      'Max 30 seconds — longer videos are trimmed to their first 30 seconds. Show your product in action.',
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                    SizedBox(height: context.rh(8)),
                    if (_selectedVideos.isNotEmpty ||
                        _existingVideoUrls.isNotEmpty)
                      SizedBox(
                        height: context.rh(160),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ..._selectedVideos.asMap().entries.map((entry) {
                              final index = entry.key;
                              return Padding(
                                padding: EdgeInsets.only(right: context.rw(8)),
                                child: Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _removeVideo(index),
                                      child: Container(
                                        width: context.rw(140),
                                        height: context.rh(160),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(
                                            context.rr(12),
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            context.rr(12),
                                          ),
                                          child:
                                              index <
                                                      _videoPreviewControllers
                                                          .length &&
                                                  _videoPreviewControllers[index] !=
                                                      null &&
                                                  _videoPreviewControllers[index]!
                                                      .value
                                                      .isInitialized
                                              ? VideoPlayer(
                                                  _videoPreviewControllers[index]!,
                                                )
                                              : Center(
                                                  child: Icon(
                                                    LucideIcons.video,
                                                    color: Colors.white54,
                                                    size: context.ri(32),
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: context.rh(4),
                                      right: context.rw(4),
                                      child: GestureDetector(
                                        onTap: () => _removeVideo(index),
                                        child: Container(
                                          padding: context.rAll(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
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
                                    Center(
                                      child: Container(
                                        padding: context.rAll(8),
                                        decoration: const BoxDecoration(
                                          color: Colors.black45,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          LucideIcons.play,
                                          color: Colors.white,
                                          size: context.ri(24),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            ..._existingVideoUrls.map((url) {
                              return Padding(
                                padding: EdgeInsets.only(right: context.rw(8)),
                                child: Stack(
                                  children: [
                                    Container(
                                      width: context.rw(140),
                                      height: context.rh(160),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(
                                          context.rr(12),
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.video,
                                          color: Colors.white54,
                                          size: context.ri(32),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: context.rh(4),
                                      right: context.rw(4),
                                      child: GestureDetector(
                                        onTap: () => _removeVideo(
                                          _existingVideoUrls.indexOf(url) +
                                              _selectedVideos.length,
                                        ),
                                        child: Container(
                                          padding: context.rAll(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
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
                                    Center(
                                      child: Container(
                                        padding: context.rAll(8),
                                        decoration: const BoxDecoration(
                                          color: Colors.black45,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          LucideIcons.play,
                                          color: Colors.white,
                                          size: context.ri(24),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            // Add more video tile
                            if (_canAddVideo)
                              GestureDetector(
                                onTap: _pickVideo,
                                child: Container(
                                  width: context.rw(80),
                                  height: context.rh(160),
                                  margin: EdgeInsets.only(right: context.rw(8)),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(
                                      context.rr(12),
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        LucideIcons.plus,
                                        size: context.ri(24),
                                        color: AppTheme.accent,
                                      ),
                                      SizedBox(height: context.rh(4)),
                                      Text(
                                        'Add',
                                        style: TextStyle(
                                          color: AppTheme.accent,
                                          fontSize: context.rsp(11),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _pickVideo,
                        child: Container(
                          height: context.rh(120),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(context.rr(12)),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.video,
                                size: context.ri(32),
                                color: const Color(0xFF94A3B8),
                              ),
                              SizedBox(height: context.rh(4)),
                              Text(
                                'Record or Upload Video (max 30s)',
                                style: TextStyle(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: context.rsp(12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    SizedBox(height: context.rh(24)),

                    // Show on Clips toggle
                    Opacity(
                      opacity: _hasVideo ? 1.0 : 0.5,
                      child: Row(
                        children: [
                          SizedBox(
                            height: context.ri(20),
                            width: context.ri(20),
                            child: Checkbox(
                              value: _showOnClips,
                              onChanged: _hasVideo
                                  ? (v) => setState(
                                      () => _showOnClips = v ?? false,
                                    )
                                  : null,
                              activeColor: AppTheme.accent,
                            ),
                          ),
                          SizedBox(width: context.rw(10)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Show on Clips',
                                  style: TextStyle(
                                    fontSize: context.rsp(14),
                                    fontWeight: FontWeight.w600,
                                    color: _hasVideo
                                        ? AppTheme.charcoalInk
                                        : AppTheme.mutedSteel,
                                  ),
                                ),
                                Text(
                                  _hasVideo
                                      ? 'Your product video will appear in the Clips feed'
                                      : 'Add a video to enable this option',
                                  style: TextStyle(
                                    fontSize: context.rsp(11),
                                    color: AppTheme.mutedSteel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_needsClipVideoSelection)
                      _buildClipVideoSelector(context),

                    SizedBox(height: context.rh(24)),

                    Container(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _isAIProcessing ? null : _autoFillWithAI,
                        icon: _isAIProcessing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF6366F1),
                                ),
                              )
                            : const Icon(
                                LucideIcons.sparkles,
                                size: 16,
                                color: Color(0xFF6366F1),
                              ),
                        label: Text(
                          _isAIProcessing
                              ? 'Analyzing image...'
                              : 'Auto-fill with AI',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFF6366F1),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: context.rh(16)),

                    // Title
                    ShadInputFormField(
                      id: 'title',
                      controller: _titleController,
                      label: RequiredLabel('Title'),
                      placeholder: const Text('What are you selling?'),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value.isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: context.rh(16)),

                    // Price
                    ShadInputFormField(
                      id: 'price',
                      controller: _priceController,
                      label: RequiredLabel('Price'),
                      placeholder: const Text('0.00'),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      leading: Padding(
                        padding: EdgeInsets.only(left: context.rw(12)),
                        child: Text(
                          'GH\u00a2',
                          style: TextStyle(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                            fontSize: context.rsp(14),
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value.isEmpty) {
                          return 'Please enter a price';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid price';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Category
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        _showCategorySearchSheet(
                          context,
                          productProv.categories,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _selectedCategoryId == null
                                    ? 'Select a Category'
                                    : _selectedCategoryName(productProv),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _selectedCategoryId == null
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF1E293B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              LucideIcons.chevronDown,
                              color: Color(0xFF64748B),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Condition
                    RequiredLabel(
                      'Condition',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ProductCondition.values.map((condition) {
                        final isSelected = _selectedCondition == condition;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCondition = condition;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              condition.displayName,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Description
                    ShadInputFormField(
                      id: 'description',
                      controller: _descriptionController,
                      label: RequiredLabel('Description'),
                      placeholder: const Text(
                        'Describe your item in detail...',
                      ),
                      maxLines: 5,
                      validator: (value) {
                        if (value.isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Campus (Required) — or publish for all institutions
                    GestureDetector(
                      onTap: () => setState(() {
                        _allInstitutions = !_allInstitutions;
                        if (_allInstitutions) {
                          _selectedCampuses = [];
                          _institutionDeliveryFees = {};
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _allInstitutions
                              ? AppTheme.accent.withValues(alpha: 0.08)
                              : AppTheme.pureSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _allInstitutions
                                ? AppTheme.accent
                                : AppTheme.whisperBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.globe,
                              size: 18,
                              color: _allInstitutions
                                  ? AppTheme.accent
                                  : AppTheme.mutedSteel,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'All Institutions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.charcoalInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Any buyer can view and purchase this product, regardless of their institution.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              _allInstitutions
                                  ? LucideIcons.checkCircle2
                                  : LucideIcons.circle,
                              size: 20,
                              color: _allInstitutions
                                  ? AppTheme.accent
                                  : AppTheme.mutedSteel,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!_allInstitutions) ...[
                      const SizedBox(height: 16),
                      MultiInstitutionPicker(
                        selectedValues: _selectedCampuses,
                        onChanged: (vals) => setState(() {
                          _selectedCampuses = vals;
                          _institutionDeliveryFees = {
                            for (final c in vals)
                              c: _institutionDeliveryFees[c] ?? 0.0,
                          };
                        }),
                        label: 'Campuses / Locations',
                        isRequired: true,
                        hint: 'Select campuses...',
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Delivery fee applies to all institutions for this listing.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.mutedSteel,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Stock Quantity
                    ShadInputFormField(
                      id: 'stock',
                      controller: _stockController,
                      label: RequiredLabel('Stock Quantity'),
                      placeholder: const Text('1'),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value.isEmpty) {
                          return 'Please enter a stock quantity';
                        }
                        final quantity = int.tryParse(value);
                        if (quantity == null || quantity <= 0) {
                          return 'Please enter a valid stock quantity (> 0)';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Delivery Option
                    const Text(
                      'Delivery Option',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            {'value': 'pickup', 'label': 'Pickup Only'},
                            {'value': 'delivery', 'label': 'Delivery Only'},
                            {
                              'value': 'both',
                              'label': 'Both (Pickup & Delivery)',
                            },
                          ].map((opt) {
                            final isSelected = _deliveryOption == opt['value'];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _deliveryOption = opt['value']!;
                                  if (_deliveryOption == 'pickup') {
                                    _deliveryFeeController.text = '0.00';
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  opt['label']!,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),

                    if (_deliveryOption != 'pickup') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ShadInputFormField(
                              id: 'deliveryFee',
                              controller: _deliveryFeeController,
                              label: RequiredLabel('Delivery Fee'),
                              placeholder: const Text('0.00'),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              leading: const Padding(
                                padding: EdgeInsets.only(left: 12),
                                child: Text(
                                  'GH\u00a2',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (_deliveryOption == 'pickup') return null;
                                if (value.isEmpty) {
                                  return 'Please enter a delivery fee';
                                }
                                if (double.tryParse(value) == null) {
                                  return 'Please enter a valid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                          if (_selectedCampuses.length > 1) ...[
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Same for all',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Switch(
                                  value: _useSameDeliveryFee,
                                  onChanged: (val) => setState(() {
                                    _useSameDeliveryFee = val;
                                    if (val) {
                                      final fee =
                                          double.tryParse(
                                            _deliveryFeeController.text.trim(),
                                          ) ??
                                          0.0;
                                      _institutionDeliveryFees = {
                                        for (final c in _selectedCampuses)
                                          c: fee,
                                      };
                                    }
                                  }),
                                  activeThumbColor: AppTheme.accent,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      if (!_useSameDeliveryFee &&
                          _selectedCampuses.length > 1) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.pureSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.whisperBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Per-Campus Delivery Fees',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.charcoalInk,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(_selectedCampuses.length, (i) {
                                final campus = _selectedCampuses[i];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: i < _selectedCampuses.length - 1
                                        ? 8
                                        : 0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          campus,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.charcoalInk,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: ShadInput(
                                          initialValue:
                                              _institutionDeliveryFees[campus]
                                                  ?.toStringAsFixed(2) ??
                                              '0.00',
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          leading: const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Text(
                                              'GH\u00a2',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                          onChanged: (val) {
                                            final fee =
                                                double.tryParse(val) ?? 0.0;
                                            setState(
                                              () =>
                                                  _institutionDeliveryFees[campus] =
                                                      fee,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // Discount Section (Optional)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.pureSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.whisperBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.badgePercent,
                                size: 18,
                                color: AppTheme.accent,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Discount (Optional)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _hasDiscount,
                                onChanged: (val) =>
                                    setState(() => _hasDiscount = val),
                                activeThumbColor: AppTheme.accent,
                              ),
                            ],
                          ),
                          if (_hasDiscount) ...[
                            const SizedBox(height: 16),
                            ShadInputFormField(
                              id: 'discountPercent',
                              controller: _discountPercentController,
                              label: const Text('Discount Percentage'),
                              placeholder: const Text('e.g. 15'),
                              keyboardType: TextInputType.number,
                              leading: const Padding(
                                padding: EdgeInsets.only(left: 12),
                                child: Text(
                                  '%',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value.isEmpty) return null;
                                final pct = double.tryParse(value);
                                if (pct == null || pct <= 0 || pct > 90) {
                                  return 'Enter a valid percentage (1-90)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDateField(
                                    label: 'Start Date',
                                    date: _discountStartDate,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _discountStartDate ??
                                            DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 365),
                                        ),
                                      );
                                      if (picked != null) {
                                        setState(
                                          () => _discountStartDate = picked,
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildDateField(
                                    label: 'Expiry Date',
                                    date: _discountEndDate,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _discountEndDate ??
                                            DateTime.now().add(
                                              const Duration(days: 7),
                                            ),
                                        firstDate:
                                            _discountStartDate ??
                                            DateTime.now(),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 365),
                                        ),
                                      );
                                      if (picked != null) {
                                        setState(
                                          () => _discountEndDate = picked,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (_discountPercentController.text.isNotEmpty &&
                                _discountStartDate != null &&
                                _discountEndDate != null &&
                                double.tryParse(
                                      _discountPercentController.text,
                                    ) !=
                                    null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.successMoss.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.tag,
                                      size: 14,
                                      color: AppTheme.successMoss,
                                    ),
                                    const SizedBox(width: 8),
                                    Builder(
                                      builder: (context) {
                                        final priceVal = double.tryParse(
                                          _priceController.text,
                                        );
                                        final discountVal = double.tryParse(
                                          _discountPercentController.text,
                                        );
                                        if (priceVal == null ||
                                            discountVal == null ||
                                            discountVal <= 0) {
                                          return const SizedBox.shrink();
                                        }
                                        final discounted =
                                            priceVal * (1 - discountVal / 100);
                                        return Text(
                                          'Price: ${formatGhs(priceVal)} → ${formatGhs(discounted)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.successMoss,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Specifications
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RequiredLabel(
                          'Specifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        ShadButton.ghost(
                          onPressed: () => _addSpec(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.plus, size: 16),
                              const SizedBox(width: 4),
                              const Text('Add'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_specifications.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Add specifications like color, size, brand, etc.',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ..._specifications.asMap().entries.map((entry) {
                        final i = entry.key;
                        final pair = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: ShadInput(
                                  controller: pair.keyController,
                                  placeholder: const Text('Key (e.g. Color)'),
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ShadInput(
                                  controller: pair.valueController,
                                  placeholder: const Text('Value (e.g. Black)'),
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const SizedBox(width: 4),
                              ShadIconButton.ghost(
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                onPressed: () => _removeSpec(i),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
            ),
            const SizedBox(height: 4),
            Text(
              date != null
                  ? DateFormat('dd MMM yyyy').format(date)
                  : 'Select date',
              style: TextStyle(
                fontSize: 13,
                color: date != null
                    ? AppTheme.charcoalInk
                    : AppTheme.mutedSteel,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _selectedCategoryName(ProductProvider provider) {
    final cat = provider.categories.where((c) => c.id == _selectedCategoryId);
    return cat.isNotEmpty ? cat.first.name : _selectedCategoryId!;
  }

  void _showCategorySearchSheet(
    BuildContext context,
    List<Category> categories,
  ) {
    showShadSheet(
      context: context,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final keyboardHeight = mediaQuery.viewInsets.bottom;
        final screenHeight = mediaQuery.size.height;
        final maxContentHeight = screenHeight * 0.5;

        // Avoid overflow when keyboard is open
        final availableHeight = screenHeight - keyboardHeight - 120;
        final contentHeight = maxContentHeight > availableHeight
            ? (availableHeight > 100 ? availableHeight : 100.0)
            : maxContentHeight;

        return ShadSheet(
          title: const Text('Select Category'),
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SizedBox(
              height: contentHeight,
              child: _CategorySearchContent(
                categories: categories,
                initialSelectedId: _selectedCategoryId,
                onSelected: (categoryId) {
                  setState(() {
                    _selectedCategoryId = categoryId;
                  });
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpecPair {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _SpecPair({required this.keyController, required this.valueController});
}

class _CategorySearchContent extends StatefulWidget {
  final List<Category> categories;
  final String? initialSelectedId;
  final ValueChanged<String?> onSelected;

  const _CategorySearchContent({
    required this.categories,
    required this.initialSelectedId,
    required this.onSelected,
  });

  @override
  State<_CategorySearchContent> createState() => _CategorySearchContentState();
}

class _CategorySearchContentState extends State<_CategorySearchContent> {
  List<Category> _filteredCategories = [];

  @override
  void initState() {
    super.initState();
    _filteredCategories = widget.categories;
  }

  void _filterCategories(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCategories = widget.categories;
      } else {
        _filteredCategories = widget.categories
            .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ShadInput(
            placeholder: const Text('Search categories...'),
            onChanged: _filterCategories,
          ),
        ),
        Expanded(
          child: _filteredCategories.isEmpty
              ? const Center(
                  child: Text(
                    'No categories found',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredCategories.length,
                  itemBuilder: (context, index) {
                    final category = _filteredCategories[index];
                    final isSelected = widget.initialSelectedId == category.id;
                    return GestureDetector(
                      onTap: () {
                        widget.onSelected(category.id);
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                category.name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                LucideIcons.check,
                                color: Color(0xFF6366F1),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
