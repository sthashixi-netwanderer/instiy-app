import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';
import '../../models/service_model.dart';
import '../../models/category_model.dart';
import '../../models/picked_media.dart';
import '../../services/service_service.dart';
import '../../providers/providers.dart';
import '../../widgets/image_picker_sheet.dart';
import '../../widgets/multi_institution_picker.dart';
import '../../widgets/ai_enhance_button.dart';
import '../../widgets/required_label.dart';
import '../../services/ai_service.dart';

/// Service creation wizard (Fiverr-style). Also handles editing when
/// [existingService] is provided. Reachable only from the Services screen.
class CreateServiceScreen extends ConsumerStatefulWidget {
  final Service? existingService;

  const CreateServiceScreen({super.key, this.existingService});

  @override
  ConsumerState<CreateServiceScreen> createState() =>
      _CreateServiceScreenState();
}

const _deliveryUnits = ['minutes', 'hours', 'days', 'months', 'years'];

/// Draft fields for one pricing tier. Basic is always present; Standard and
/// Premium can be toggled on.
class _PackageDraft {
  final ServiceTier tier;
  final TextEditingController name = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController deliveryDuration = TextEditingController();
  String deliveryUnit = 'days';
  final TextEditingController revisions = TextEditingController();
  bool isPopular = false;
  bool enabled;
  final List<TextEditingController> featureCtrls = [];

  _PackageDraft(this.tier, {this.enabled = false});

  factory _PackageDraft.basic() {
    final d = _PackageDraft(ServiceTier.basic, enabled: true);
    d.name.text = 'Basic';
    d.deliveryDuration.text = '3';
    d.deliveryUnit = 'days';
    d.revisions.text = '1';
    d.addFeature();
    return d;
  }

  void addFeature([String text = '']) {
    featureCtrls.add(TextEditingController(text: text));
  }

  void removeFeature(int index) {
    if (index >= 0 && index < featureCtrls.length) {
      featureCtrls[index].dispose();
      featureCtrls.removeAt(index);
    }
  }

  List<String> get features => featureCtrls
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  String get displayName =>
      name.text.trim().isNotEmpty ? name.text.trim() : tier.displayName;

  String get deliveryTimeFormatted {
    final duration = int.tryParse(deliveryDuration.text.trim()) ?? 1;
    final unit = deliveryUnit.toLowerCase().trim();
    if (unit.contains('min')) {
      return '$duration minute${duration == 1 ? '' : 's'}';
    } else if (unit.contains('hour') || unit.contains('hr')) {
      return '$duration hour${duration == 1 ? '' : 's'}';
    } else if (unit.contains('month') || unit.contains('mo')) {
      return '$duration month${duration == 1 ? '' : 's'}';
    } else if (unit.contains('year') || unit.contains('yr')) {
      return '$duration year${duration == 1 ? '' : 's'}';
    } else {
      return '$duration day${duration == 1 ? '' : 's'}';
    }
  }

  void populate(ServicePackage p) {
    enabled = true;
    name.text = p.name.isNotEmpty ? p.name : p.tier.displayName;
    description.text = p.description;
    price.text = p.price == p.price.roundToDouble()
        ? p.price.round().toString()
        : p.price.toString();
    deliveryDuration.text = p.deliveryDuration.toString();
    deliveryUnit = p.deliveryUnit;
    revisions.text = p.revisions.toString();
    isPopular = p.isPopular;

    for (final c in featureCtrls) {
      c.dispose();
    }
    featureCtrls.clear();
    for (final feat in p.features) {
      addFeature(feat);
    }
    if (featureCtrls.isEmpty) {
      addFeature();
    }
  }

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    deliveryDuration.dispose();
    revisions.dispose();
    for (final c in featureCtrls) {
      c.dispose();
    }
  }
}

class _CreateServiceScreenState extends ConsumerState<CreateServiceScreen> {
  static const _steps = ['Overview', 'Details', 'Packages', 'Review'];

  bool get _isEditing => widget.existingService != null;

  int _currentStep = 0;
  bool _isPublishing = false;

  /// Whether the provider offers tiered packages. Default on; turning it
  /// off publishes a single-price service. Creating packages requires at
  /// least one gallery image of the service.
  bool _packagesEnabled = true;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  /// Price used when packages are toggled off (services.price is NOT NULL).
  final _basePriceCtrl = TextEditingController();

  Category? _selectedCategory;
  List<Category> _categories = [];

  /// Institution names restricting where the listing shows. Empty + not
  /// [_allInstitutions] means unrestricted ("All institutions"), same rule
  /// as product listings.
  List<String> _selectedInstitutions = [];
  bool _allInstitutions = true;

  final List<PickedMedia> _newImages = [];
  List<String> _existingImageUrls = [];

  late final List<_PackageDraft> _packages = [
    _PackageDraft.basic(),
    _PackageDraft(ServiceTier.standard),
    _PackageDraft(ServiceTier.premium),
  ];

  @override
  void initState() {
    super.initState();
    // Rebuild as the user types so the Continue/Publish button reflects
    // whether the current step's required fields are satisfied.
    for (final ctrl in [
      _titleCtrl,
      _descCtrl,
      _tagsCtrl,
      _basePriceCtrl,
      ..._packages.expand(
        (p) => [
          p.name,
          p.description,
          p.price,
          p.deliveryDuration,
          p.revisions,
        ],
      ),
    ]) {
      ctrl.addListener(_onFieldChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }
    final isProvider = await ServiceService.isServiceProvider();
    if (!mounted) return;
    if (!isProvider) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          title: Text('Provider access required'),
          description: Text(
            'Your service provider status is disabled. You cannot create or edit services.',
          ),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    if (widget.existingService != null &&
        widget.existingService!.providerId != auth.user?.id) {
      Navigator.of(context).pop();
      return;
    }

    try {
      _categories = await ServiceService.getServiceCategories();
    } catch (_) {}
    if (!mounted) return;

    final existing = widget.existingService;
    if (existing != null) {
      _titleCtrl.text = existing.title;
      _descCtrl.text = existing.description ?? '';
      _tagsCtrl.text = existing.searchTags.join(', ');
      _existingImageUrls = [...existing.imageUrls];
      _selectedCategory = _categories
          .where((c) => c.id == existing.categoryId)
          .firstOrNull;
      _packagesEnabled = existing.packages.isNotEmpty;
      _basePriceCtrl.text = existing.price == existing.price.roundToDouble()
          ? existing.price.round().toString()
          : existing.price.toString();
      if (existing.institutionCodes.isEmpty) {
        _allInstitutions = true;
      } else {
        _allInstitutions = false;
        _selectedInstitutions = [...existing.institutionCodes];
      }
      for (final draft in _packages) {
        final match = existing.packages
            .where((p) => p.tier == draft.tier)
            .firstOrNull;
        if (match != null) draft.populate(match);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    _basePriceCtrl.dispose();
    for (final p in _packages) {
      p.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------
  // Validation
  // ------------------------------------------------------------

  List<String> get _parsedTags => _tagsCtrl.text
      .split(',')
      .map((t) => t.trim().toLowerCase())
      .where((t) => t.isNotEmpty)
      .toList();

  int get _totalImageCount => _existingImageUrls.length + _newImages.length;

  List<_PackageDraft> get _enabledPackages =>
      _packages.where((p) => p.enabled).toList();

  /// Package drafts that will actually be saved — the toggle gates them all.
  List<_PackageDraft> get _activePackages =>
      _packagesEnabled ? _enabledPackages : const [];

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_titleCtrl.text.trim().length < 8) {
          return 'Give your service a title of at least 8 characters';
        }
        if (_selectedCategory == null) return 'Pick a category';
        if (!_allInstitutions && _selectedInstitutions.isEmpty) {
          return 'Pick at least one institution, or switch to all institutions';
        }
        if (_parsedTags.length > 8) return 'Use at most 8 search tags';
        return null;
      case 1:
        if (_descCtrl.text.trim().length < 20) {
          return 'Describe your service in at least 20 characters';
        }
        if (_totalImageCount == 0) {
          return 'Add at least one image so customers can see your work';
        }
        return null;
      case 2:
        if (!_packagesEnabled) {
          final basePrice = double.tryParse(_basePriceCtrl.text.trim());
          if (basePrice == null || basePrice <= 0) {
            return 'Set a starting price above 0 for your service';
          }
          return null;
        }
        if (_totalImageCount == 0) {
          return 'Add at least one image of your service before creating packages';
        }
        for (final p in _enabledPackages) {
          if (p.displayName.isEmpty) {
            return 'Name your ${p.tier.displayName} package';
          }
          final price = double.tryParse(p.price.text.trim());
          if (price == null || price <= 0) {
            return 'Set a price above 0 for the ${p.displayName} package';
          }
          final duration = int.tryParse(p.deliveryDuration.text.trim());
          if (duration == null || duration < 1) {
            return 'Enter a valid delivery time for ${p.displayName}';
          }
          final revisions = int.tryParse(p.revisions.text.trim());
          if (revisions == null || revisions < 0 || revisions > 99) {
            return 'Revisions for ${p.displayName} must be 0–99';
          }
        }
        return null;
      default:
        return null;
    }
  }

  // ------------------------------------------------------------
  // Publish
  // ------------------------------------------------------------

  Future<void> _publish() async {
    for (var step = 0; step < 3; step++) {
      final error = _validateStep(step);
      if (error != null) {
        _toast(error);
        setState(() => _currentStep = step);
        return;
      }
    }

    setState(() => _isPublishing = true);
    try {
      // Upload newly picked images first.
      final uploaded = await ServiceService.uploadServiceImages(_newImages);
      final imageUrls = [..._existingImageUrls, ...uploaded];

      final enabled = _activePackages;
      final packageModels = enabled
          .map(
            (p) {
              final duration = int.parse(p.deliveryDuration.text.trim());
              final unit = p.deliveryUnit;
              final days = unit == 'minutes' || unit == 'hours'
                  ? 0
                  : (unit == 'months'
                      ? duration * 30
                      : (unit == 'years' ? duration * 365 : duration));
              return ServicePackage(
                tier: p.tier,
                name: p.displayName,
                description: p.description.text.trim(),
                price: double.parse(p.price.text.trim()),
                deliveryDays: days,
                deliveryDuration: duration,
                deliveryUnit: unit,
                revisions: int.parse(p.revisions.text.trim()),
                isPopular: p.isPopular,
                features: p.features,
              );
            },
          )
          .toList();
      // Without packages the service sells at a single base price; keep the
      // previous delivery estimate when editing.
      final double startingPrice;
      final int? deliveryDays;
      if (packageModels.isEmpty) {
        startingPrice = double.parse(_basePriceCtrl.text.trim());
        deliveryDays = widget.existingService?.deliveryDays;
      } else {
        startingPrice = packageModels
            .map((p) => p.price)
            .reduce((a, b) => a < b ? a : b);
        deliveryDays = packageModels
            .map((p) => p.deliveryDays)
            .reduce((a, b) => a < b ? a : b);
      }
      // "All institutions" persists as an empty list (matches products).
      final institutionCodes = _allInstitutions
          ? <String>[]
          : List<String>.from(_selectedInstitutions);

      final provider = ref.read(serviceProvider);
      final existing = widget.existingService;
      final result = existing == null
          ? await provider.createService(
              title: _titleCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              categoryId: _selectedCategory!.id,
              categoryName: _selectedCategory!.name,
              price: startingPrice,
              deliveryDays: deliveryDays,
              imageUrls: imageUrls,
              institutionCodes: institutionCodes,
              searchTags: _parsedTags,
              packages: packageModels,
            )
          : await provider.updateService(
              existing.id,
              title: _titleCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              categoryId: _selectedCategory!.id,
              categoryName: _selectedCategory!.name,
              price: startingPrice,
              deliveryDays: deliveryDays,
              imageUrls: imageUrls,
              institutionCodes: institutionCodes,
              searchTags: _parsedTags,
              packages: packageModels,
            );

      if (!mounted) return;
      if (result == true) {
        ShadToaster.of(context).show(
          ShadToast(
            title: Text(
              _isEditing ? 'Service updated' : 'Service published!',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() => _isPublishing = false);
        _toast('Couldn\'t save the service: $result');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      _toast('Couldn\'t save the service: $e');
    }
  }

  void _toast(String message) {
    ShadToaster.of(context).show(ShadToast(title: Text(message)));
  }

  // ------------------------------------------------------------
  // Step navigation
  // ------------------------------------------------------------

  void _next() {
    final error = _validateStep(_currentStep);
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _currentStep = (_currentStep + 1).clamp(0, _steps.length - 1));
  }

  // ------------------------------------------------------------
  // Images
  // ------------------------------------------------------------

  Future<void> _pickImages() async {
    final picked = await ImagePickerSheet.pickMultiple(context);
    if (picked.isNotEmpty) {
      setState(() => _newImages.addAll(picked));
    }
  }

  void _removeNewImage(int index) =>
      setState(() => _newImages.removeAt(index));

  void _removeExistingImage(int index) =>
      setState(() => _existingImageUrls.removeAt(index));

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text(_isEditing ? 'Edit Service' : 'Create Service'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: context.rw(12)),
            child: Text(
              'Step ${_currentStep + 1} of ${_steps.length}',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
          ),
        ],
      ),
      // Same tap-to-dismiss behavior ResponsiveLayout gives screens that
      // use it; this screen builds its own Scaffold.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final currentFocus = FocusScope.of(context);
          if (!currentFocus.hasPrimaryFocus &&
              currentFocus.focusedChild != null) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        },
        child: Column(
          children: [
            SizedBox(
            height: MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
          ),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  context.rw(16),
                  context.rh(8),
                  context.rw(16),
                  context.rh(90),
                ),
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildNavigationButtons(),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: context.rh(4),
                decoration: BoxDecoration(
                  color: i <= _currentStep
                      ? AppTheme.accent
                      : AppTheme.whisperBorder,
                  borderRadius: BorderRadius.circular(context.rr(4)),
                ),
              ),
            ),
            if (i < _steps.length - 1) SizedBox(width: context.rw(4)),
          ],
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildOverviewStep();
      case 1:
        return _buildDetailsStep();
      case 2:
        return _buildPackagesStep();
      default:
        return _buildReviewStep();
    }
  }

  // Step 1: title, category, tags --------------------------------

  Widget _buildOverviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Overview',
          'Start with the basics — what do you offer and how can customers find it?',
        ),
        ShadInputFormField(
          id: 'title',
          controller: _titleCtrl,
          label: RequiredLabel('Service title'),
          placeholder: const Text('e.g. I will design a logo for your brand'),
          textInputAction: TextInputAction.next,
        ),
        SizedBox(height: context.rh(16)),
        RequiredLabel(
          'Category',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(14),
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(8)),
        GestureDetector(
          onTap: _showCategorySheet,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rw(14),
              vertical: context.rh(14),
            ),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(10)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  size: context.ri(16),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(8)),
                Expanded(
                  child: Text(
                    _selectedCategory?.name ?? 'Choose a category',
                    style: TextStyle(
                      fontSize: context.rsp(14),
                      color: _selectedCategory != null
                          ? AppTheme.charcoalInk
                          : AppTheme.mutedSteel,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: context.ri(16),
                  color: AppTheme.mutedSteel,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.rh(16)),
        Text(
          'Availability',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(14),
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(8)),
        _buildAllInstitutionsToggle(),
        if (!_allInstitutions) ...[
          SizedBox(height: context.rh(10)),
          MultiInstitutionPicker(
            selectedValues: _selectedInstitutions,
            onChanged: (values) =>
                setState(() => _selectedInstitutions = values),
            label: 'Institutions',
            isRequired: true,
            hint: 'Select institutions...',
          ),
        ],
        SizedBox(height: context.rh(16)),
        ShadInputFormField(
          id: 'tags',
          controller: _tagsCtrl,
          label: const Text('Search tags (optional)'),
          placeholder: const Text('logo, branding, flyer — comma separated'),
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _buildAllInstitutionsToggle() {
    return GestureDetector(
      onTap: () => setState(() {
        _allInstitutions = !_allInstitutions;
        if (_allInstitutions) _selectedInstitutions = [];
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: _allInstitutions
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: _allInstitutions
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: context.rAll(10),
              decoration: BoxDecoration(
                color: _allInstitutions
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(10)),
              ),
              child: Icon(
                LucideIcons.globe,
                size: context.ri(18),
                color: _allInstitutions
                    ? AppTheme.accent
                    : AppTheme.mutedSteel,
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All institutions',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                      color: _allInstitutions
                          ? AppTheme.accent
                          : AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Text(
                    'Customers at any institution can find this service',
                    style: TextStyle(
                      fontSize: context.rsp(12),
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
              size: context.ri(20),
              color: _allInstitutions
                  ? AppTheme.accent
                  : AppTheme.mutedSteel,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCategorySheet() async {
    final Category? selected = await showShadSheet<Category>(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Choose a category'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _categories.length,
                itemBuilder: (ctx, index) {
                  final category = _categories[index];
                  final isSelected = category.id == _selectedCategory?.id;
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                    title: Text(
                      category.name,
                      style: TextStyle(
                        fontSize: context.rsp(14),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.accent
                            : AppTheme.charcoalInk,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                            LucideIcons.check,
                            size: context.ri(18),
                            color: AppTheme.accent,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(category),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: context.rh(8)),
          ],
        ),
      ),
    );
    if (selected != null) {
      setState(() => _selectedCategory = selected);
    }
  }

  // Step 2: description + gallery --------------------------------

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Details',
          'Explain what customers get and show your work with images.',
        ),
        ShadInputFormField(
          id: 'description',
          controller: _descCtrl,
          label: RequiredLabel('Description'),
          placeholder: const Text(
            'What\'s included, how you work, what you need from the customer...',
          ),
          maxLines: 6,
          keyboardType: TextInputType.multiline,
        ),
        SizedBox(height: context.rh(8)),
        // AI enhancer — bottom-right of the description field.
        AiEnhanceButton(
          controller: _descCtrl,
          enhance: AIService.enhanceServiceDescription,
        ),
        SizedBox(height: context.rh(8)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RequiredLabel(
              'Gallery ($_totalImageCount)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(14),
                color: AppTheme.charcoalInk,
              ),
            ),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: _pickImages,
              leading: const Icon(LucideIcons.plus, size: 14),
              child: const Text('Add'),
            ),
          ],
        ),
        SizedBox(height: context.rh(8)),
        if (_totalImageCount == 0)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: double.infinity,
              padding: context.rAll(24),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(context.rr(12)),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.imagePlus,
                    size: context.ri(28),
                    color: AppTheme.mutedSteel,
                  ),
                  SizedBox(height: context.rh(6)),
                  Text(
                    'Add images of your work',
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _totalImageCount,
            itemBuilder: (context, index) {
              if (index < _existingImageUrls.length) {
                final url = _existingImageUrls[index];
                final imageIndex = index;
                return _GalleryTile(
                  onRemove: () => _removeExistingImage(imageIndex),
                  badge: 'saved',
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 240,
                    placeholder: (_, _) =>
                        Container(color: AppTheme.warmMist),
                    errorWidget: (_, _, _) =>
                        Container(color: AppTheme.warmMist),
                  ),
                );
              }
              final newIdx = index - _existingImageUrls.length;
              final media = _newImages[newIdx];
              return _GalleryTile(
                onRemove: () => _removeNewImage(newIdx),
                badge: 'new',
                child: Image.memory(
                  media.bytes,
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
      ],
    );
  }

  // Step 3: packages ----------------------------------------------

  Widget _buildPackagesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Packages & Plans',
          _packagesEnabled
              ? 'Offer tiers so customers can pick the level of service they need. '
                  'You can customize package names, delivery duration/units, add vertical features, and mark a popular plan.'
              : 'Packages are off — your service is offered at a single starting price.',
        ),
        _buildPackagesToggle(),
        SizedBox(height: context.rh(16)),
        if (_packagesEnabled)
          for (final draft in _packages) _buildPackageEditor(draft)
        else ...[
          ShadInputFormField(
            id: 'base-price',
            controller: _basePriceCtrl,
            label: RequiredLabel('Starting price (GH₵)'),
            placeholder: const Text('150'),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textInputAction: TextInputAction.done,
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Customers will contact you about this price. You can add packages '
            'later by editing the service.',
            style: TextStyle(
              fontSize: context.rsp(12),
              color: AppTheme.mutedSteel,
            ),
          ),
        ],
      ],
    );
  }

  /// Master switch for packages. Defaults to on; enabling requires at least
  /// one service image so every tiered listing shows the provider's work.
  Widget _buildPackagesToggle() {
    final canUsePackages = _totalImageCount > 0;
    return GestureDetector(
      onTap: () => _setPackagesEnabled(!_packagesEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: _packagesEnabled
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: _packagesEnabled
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: context.rAll(10),
              decoration: BoxDecoration(
                color: _packagesEnabled
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.warmMist,
                borderRadius: BorderRadius.circular(context.rr(10)),
              ),
              child: Icon(
                LucideIcons.layers,
                size: context.ri(18),
                color: _packagesEnabled
                    ? AppTheme.accent
                    : AppTheme.mutedSteel,
              ),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offer packages / plans',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                      color: _packagesEnabled
                          ? AppTheme.accent
                          : AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Text(
                    canUsePackages
                        ? (_packagesEnabled
                              ? 'Customers pick a plan (Basic, Standard, Premium) before contacting you'
                              : 'Off — your service is listed at one starting price')
                        : 'Add at least one image of your service (Details step) to create packages',
                    style: TextStyle(
                      fontSize: context.rsp(12),
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
            ShadSwitch(
              value: _packagesEnabled,
              onChanged: _setPackagesEnabled,
            ),
          ],
        ),
      ),
    );
  }

  void _setPackagesEnabled(bool value) {
    if (value && _totalImageCount == 0) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          title: Text('Add a service image first'),
          description: Text(
            'Upload at least one image of your service in the Details step '
            'before creating packages.',
          ),
        ),
      );
      return;
    }
    setState(() => _packagesEnabled = value);
  }

  Widget _buildPackageEditor(_PackageDraft draft) {
    final isBasic = draft.tier == ServiceTier.basic;
    final isPopular = draft.isPopular;

    return Container(
      margin: EdgeInsets.only(bottom: context.rh(16)),
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(
          color: isPopular
              ? AppTheme.accent
              : (draft.enabled
                  ? AppTheme.accent.withValues(alpha: 0.4)
                  : AppTheme.whisperBorder),
          width: isPopular ? 2.0 : 1.0,
        ),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                draft.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.rsp(16),
                  color: draft.enabled
                      ? AppTheme.charcoalInk
                      : AppTheme.mutedSteel,
                ),
              ),
              if (isPopular) ...[
                SizedBox(width: context.rw(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(8),
                    vertical: context.rh(3),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Text(
                    'POPULAR',
                    style: TextStyle(
                      fontSize: context.rsp(10),
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (isBasic)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rw(8),
                    vertical: context.rh(3),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warmMist,
                    borderRadius: BorderRadius.circular(context.rr(8)),
                  ),
                  child: Text(
                    'Required',
                    style: TextStyle(
                      fontSize: context.rsp(10),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                )
              else
                ShadSwitch(
                  value: draft.enabled,
                  onChanged: (v) => setState(() => draft.enabled = v),
                ),
            ],
          ),
          if (draft.enabled) ...[
            SizedBox(height: context.rh(14)),
            // Custom Package Title
            ShadInputFormField(
              id: '${draft.tier.name}-name',
              controller: draft.name,
              label: RequiredLabel('Package title / name'),
              placeholder: Text(draft.tier.displayName),
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: context.rh(12)),

            // Popular Plan Toggle
            GestureDetector(
              onTap: () {
                setState(() {
                  draft.isPopular = !draft.isPopular;
                  if (draft.isPopular) {
                    for (final p in _packages) {
                      if (p != draft) p.isPopular = false;
                    }
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: context.rAll(12),
                decoration: BoxDecoration(
                  color: isPopular
                      ? AppTheme.accent.withValues(alpha: 0.08)
                      : AppTheme.warmMist,
                  borderRadius: BorderRadius.circular(context.rr(12)),
                  border: Border.all(
                    color: isPopular
                        ? AppTheme.accent.withValues(alpha: 0.5)
                        : AppTheme.whisperBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPopular ? Icons.star : Icons.star_border,
                      size: context.ri(20),
                      color: isPopular ? AppTheme.accent : AppTheme.mutedSteel,
                    ),
                    SizedBox(width: context.rw(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mark as Popular / Recommended Plan',
                            style: TextStyle(
                              fontSize: context.rsp(13),
                              fontWeight: FontWeight.w600,
                              color: isPopular
                                  ? AppTheme.accent
                                  : AppTheme.charcoalInk,
                            ),
                          ),
                          Text(
                            'Highlights this plan for customers to make it stand out',
                            style: TextStyle(
                              fontSize: context.rsp(11),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ShadSwitch(
                      value: isPopular,
                      onChanged: (v) {
                        setState(() {
                          draft.isPopular = v;
                          if (v) {
                            for (final p in _packages) {
                              if (p != draft) p.isPopular = false;
                            }
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: context.rh(12)),

            // Price & Revisions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ShadInputFormField(
                    id: '${draft.tier.name}-price',
                    controller: draft.price,
                    label: RequiredLabel('Price (GH₵)'),
                    placeholder: const Text('150'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                SizedBox(width: context.rw(10)),
                Expanded(
                  child: ShadInputFormField(
                    id: '${draft.tier.name}-revisions',
                    controller: draft.revisions,
                    label: RequiredLabel('Revisions'),
                    placeholder: const Text('1'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(12)),

            // Delivery Time: duration + unit
            Text(
              'Delivery Time',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.rsp(14),
                color: AppTheme.charcoalInk,
              ),
            ),
            SizedBox(height: context.rh(6)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: ShadInputFormField(
                    id: '${draft.tier.name}-duration',
                    controller: draft.deliveryDuration,
                    label: RequiredLabel('Duration'),
                    placeholder: const Text('3'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                SizedBox(width: context.rw(10)),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: context.rh(8)),
                        child: Text(
                          'Unit',
                          style: TextStyle(
                            fontSize: context.rsp(14),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                      ),
                      Container(
                        height: context.rh(44),
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(12),
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.pureSurface,
                          borderRadius: BorderRadius.circular(context.rr(10)),
                          border: Border.all(color: AppTheme.whisperBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: draft.deliveryUnit,
                            isExpanded: true,
                            icon: Icon(
                              LucideIcons.chevronDown,
                              size: context.ri(16),
                              color: AppTheme.mutedSteel,
                            ),
                            items: _deliveryUnits.map((unit) {
                              return DropdownMenuItem<String>(
                                value: unit,
                                child: Text(
                                  unit[0].toUpperCase() + unit.substring(1),
                                  style: TextStyle(
                                    fontSize: context.rsp(13),
                                    color: AppTheme.charcoalInk,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (newUnit) {
                              if (newUnit != null) {
                                setState(() => draft.deliveryUnit = newUnit);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(14)),

            // Features List (Vertically Arranged)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: RequiredLabel(
                    'Features in this plan',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.rsp(14),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      draft.addFeature();
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.rw(10),
                      vertical: context.rh(5),
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(context.rr(8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.plus,
                          size: context.ri(13),
                          color: AppTheme.accent,
                        ),
                        SizedBox(width: context.rw(4)),
                        Text(
                          'Add Feature',
                          style: TextStyle(
                            fontSize: context.rsp(11),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.rh(4)),
            Text(
              'List each feature vertically with checkmarks (e.g. 1 Concept, Source files included)',
              style: TextStyle(
                fontSize: context.rsp(12),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(8)),
            for (var i = 0; i < draft.featureCtrls.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: context.rh(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: context.rAll(6),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.check,
                        size: context.ri(12),
                        color: AppTheme.accent,
                      ),
                    ),
                    SizedBox(width: context.rw(8)),
                    Expanded(
                      child: ShadInput(
                        controller: draft.featureCtrls[i],
                        placeholder: const Text('e.g. Research and exam prep'),
                      ),
                    ),
                    if (draft.featureCtrls.length > 1)
                      ShadIconButton.ghost(
                        icon: Icon(
                          LucideIcons.x,
                          size: context.ri(16),
                          color: AppTheme.mutedSteel,
                        ),
                        onPressed: () {
                          setState(() {
                            draft.removeFeature(i);
                          });
                        },
                      ),
                  ],
                ),
              ),
            SizedBox(height: context.rh(4)),
            GestureDetector(
              onTap: () {
                setState(() {
                  draft.addFeature();
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(12),
                  vertical: context.rh(8),
                ),
                decoration: BoxDecoration(
                  color: AppTheme.pureSurface,
                  borderRadius: BorderRadius.circular(context.rr(8)),
                  border: Border.all(color: AppTheme.whisperBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.plus,
                      size: context.ri(14),
                      color: AppTheme.charcoalInk,
                    ),
                    SizedBox(width: context.rw(6)),
                    Text(
                      'Add another feature',
                      style: TextStyle(
                        fontSize: context.rsp(12),
                        fontWeight: FontWeight.w500,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Step 4: review ------------------------------------------------

  Widget _buildReviewStep() {
    final enabled = _activePackages;
    final cheapest = enabled
        .map((p) => double.tryParse(p.price.text.trim()) ?? 0)
        .where((v) => v > 0)
        .toList();
    final startingPrice = cheapest.isEmpty
        ? (double.tryParse(_basePriceCtrl.text.trim()) ?? 0)
        : cheapest.reduce((a, b) => a < b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Review',
          'Double-check everything before your listing goes live.',
        ),
        if (_totalImageCount > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(context.rr(12)),
            child: SizedBox(
              height: context.rh(150),
              width: double.infinity,
              child: _existingImageUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _existingImageUrls.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) =>
                          Container(color: AppTheme.warmMist),
                    )
                  : Image.memory(_newImages.first.bytes, fit: BoxFit.cover),
            ),
          ),
        SizedBox(height: context.rh(14)),
        _reviewRow('Title', _titleCtrl.text.trim()),
        _reviewRow('Category', _selectedCategory?.name ?? '—'),
        _reviewRow(
          'Images',
          '$_totalImageCount image${_totalImageCount == 1 ? '' : 's'}',
        ),
        if (_parsedTags.isNotEmpty)
          _reviewRow('Tags', _parsedTags.join(', ')),
        _reviewRow('Starting price', formatGhs(startingPrice)),
        SizedBox(height: context.rh(10)),
        Text(
          'Description',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(14),
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(4)),
        Text(
          _descCtrl.text.trim(),
          style: TextStyle(
            fontSize: context.rsp(13),
            color: AppTheme.mutedSteel,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.rh(16)),
        Text(
          enabled.isEmpty
              ? 'Pricing'
              : 'Configured Plans (${enabled.length})',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(14),
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(8)),
        if (enabled.isEmpty)
          Container(
            width: double.infinity,
            padding: context.rAll(14),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(context.rr(12)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.tag,
                  size: context.ri(16),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(8)),
                Expanded(
                  child: Text(
                    'Single price service — customers contact you at '
                    '${formatGhs(startingPrice)}',
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < enabled.length; i++) ...[
                  _buildPlanPreviewCard(enabled[i]),
                  if (i < enabled.length - 1) SizedBox(width: context.rw(12)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlanPreviewCard(_PackageDraft draft) {
    final isPopular = draft.isPopular;
    final price = double.tryParse(draft.price.text.trim()) ?? 0;
    final revisions = int.tryParse(draft.revisions.text.trim()) ?? 1;

    return Container(
      width: context.rw(270),
      padding: context.rAll(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(
          color: isPopular ? AppTheme.accent : AppTheme.whisperBorder,
          width: isPopular ? 2.0 : 1.0,
        ),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPopular) ...[
            Text(
              'RECOMMENDED',
              style: TextStyle(
                fontSize: context.rsp(10),
                fontWeight: FontWeight.w800,
                color: AppTheme.accent,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: context.rh(4)),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.displayName,
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(6),
                  vertical: context.rh(2),
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warmMist,
                  borderRadius: BorderRadius.circular(context.rr(6)),
                ),
                child: Text(
                  draft.tier.displayName,
                  style: TextStyle(
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rh(6)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rw(8),
              vertical: context.rh(3),
            ),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(context.rr(8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.clock,
                  size: context.ri(12),
                  color: AppTheme.mutedSteel,
                ),
                SizedBox(width: context.rw(4)),
                Text(
                  draft.deliveryTimeFormatted,
                  style: TextStyle(
                    fontSize: context.rsp(11),
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(10)),
          Text(
            formatGhs(price),
            style: TextStyle(
              fontSize: context.rsp(20),
              fontWeight: FontWeight.w800,
              color: AppTheme.charcoalInk,
            ),
          ),
          Text(
            revisions >= 99
                ? 'Unlimited revisions'
                : '$revisions revision${revisions == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: context.rsp(11),
              color: AppTheme.mutedSteel,
            ),
          ),
          SizedBox(height: context.rh(12)),
          Divider(color: AppTheme.whisperBorder, height: 1),
          SizedBox(height: context.rh(10)),
          if (draft.features.isNotEmpty)
            for (final f in draft.features)
              Padding(
                padding: EdgeInsets.only(bottom: context.rh(6)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: context.rh(2)),
                      child: Icon(
                        LucideIcons.check,
                        size: context.ri(13),
                        color: isPopular ? AppTheme.accent : AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(width: context.rw(6)),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          color: AppTheme.charcoalInk,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: context.rw(110),
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: context.rsp(13),
                fontWeight: FontWeight.w500,
                color: AppTheme.charcoalInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIntro(String title, String subtitle) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.bold,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(4)),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: context.rsp(13),
              color: AppTheme.mutedSteel,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    // Continue needs the current step valid; Publish needs them all.
    final stepValid = _validateStep(_currentStep) == null;
    final allValid = [0, 1, 2].every((s) => _validateStep(s) == null);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        context.rh(8),
        context.rw(16),
        context.rh(16) + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: ShadButton.outline(
                onPressed: _isPublishing
                    ? null
                    : () => setState(() => _currentStep--),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) SizedBox(width: context.rw(12)),
          Expanded(
            flex: _currentStep == 0 ? 1 : 2,
            child: _currentStep < _steps.length - 1
                ? ShadButton(
                    onPressed: stepValid ? _next : null,
                    child: const Text('Continue'),
                  )
                : ShadButton(
                    onPressed: _isPublishing || !allValid ? null : _publish,
                    child: _isPublishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isEditing ? 'Save changes' : 'Publish service',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  final String badge;

  const _GalleryTile({
    required this.child,
    required this.onRemove,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.rr(8)),
          child: child,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.x,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rw(6),
              vertical: context.rh(2),
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(context.rr(6)),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: context.rsp(9),
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
