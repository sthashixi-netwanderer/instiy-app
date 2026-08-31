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

/// Draft fields for one pricing tier. Basic is always present; Standard and
/// Premium can be toggled on.
class _PackageDraft {
  final ServiceTier tier;
  final TextEditingController name = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController deliveryDays = TextEditingController();
  final TextEditingController revisions = TextEditingController();
  bool enabled;

  _PackageDraft(this.tier, {this.enabled = false});

  factory _PackageDraft.basic() {
    final d = _PackageDraft(ServiceTier.basic, enabled: true);
    d.deliveryDays.text = '3';
    d.revisions.text = '1';
    return d;
  }

  void populate(ServicePackage p) {
    enabled = true;
    name.text = p.name;
    description.text = p.description;
    price.text = p.price == p.price.roundToDouble()
        ? p.price.round().toString()
        : p.price.toString();
    deliveryDays.text = p.deliveryDays.toString();
    revisions.text = p.revisions.toString();
  }

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    deliveryDays.dispose();
    revisions.dispose();
  }
}

class _CreateServiceScreenState extends ConsumerState<CreateServiceScreen> {
  static const _steps = ['Overview', 'Details', 'Packages', 'Review'];

  bool get _isEditing => widget.existingService != null;

  int _currentStep = 0;
  bool _isPublishing = false;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
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
      ..._packages.expand(
        (p) => [
          p.name,
          p.description,
          p.price,
          p.deliveryDays,
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
        for (final p in _enabledPackages) {
          if (p.name.text.trim().isEmpty) {
            return 'Name your ${p.tier.displayName} package';
          }
          final price = double.tryParse(p.price.text.trim());
          if (price == null || price <= 0) {
            return 'Set a price above 0 for the ${p.tier.displayName} package';
          }
          final delivery = int.tryParse(p.deliveryDays.text.trim());
          if (delivery == null || delivery < 1 || delivery > 120) {
            return 'Delivery for ${p.tier.displayName} must be 1–120 days';
          }
          final revisions = int.tryParse(p.revisions.text.trim());
          if (revisions == null || revisions < 0 || revisions > 99) {
            return 'Revisions for ${p.tier.displayName} must be 0–99';
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

      final enabled = _enabledPackages;
      final packageModels = enabled
          .map(
            (p) => ServicePackage(
              tier: p.tier,
              name: p.name.text.trim(),
              description: p.description.text.trim(),
              price: double.parse(p.price.text.trim()),
              deliveryDays: int.parse(p.deliveryDays.text.trim()),
              revisions: int.parse(p.revisions.text.trim()),
              isPopular: p.tier == ServiceTier.standard && enabled.length > 1,
            ),
          )
          .toList();
      final startingPrice = packageModels
          .map((p) => p.price)
          .reduce((a, b) => a < b ? a : b);
      final deliveryDays = packageModels
          .map((p) => p.deliveryDays)
          .reduce((a, b) => a < b ? a : b);
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.plus, size: 14),
                  SizedBox(width: 4),
                  Text('Add'),
                ],
              ),
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
          'Packages',
          'Offer tiers so customers can pick the level of service they need. '
          'Basic is required; your cheapest tier becomes the starting price.',
        ),
        for (final draft in _packages) _buildPackageEditor(draft),
      ],
    );
  }

  Widget _buildPackageEditor(_PackageDraft draft) {
    final isBasic = draft.tier == ServiceTier.basic;
    return Container(
      margin: EdgeInsets.only(bottom: context.rh(14)),
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(14)),
        border: Border.all(
          color: draft.enabled
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.whisperBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                draft.tier.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.rsp(15),
                  color: draft.enabled
                      ? AppTheme.charcoalInk
                      : AppTheme.mutedSteel,
                ),
              ),
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
                  onChanged: (v) =>
                      setState(() => draft.enabled = v),
                ),
            ],
          ),
          if (draft.enabled) ...[
            SizedBox(height: context.rh(12)),
            ShadInputFormField(
              id: '${draft.tier.name}-name',
              controller: draft.name,
              label: RequiredLabel('Package name'),
              placeholder: const Text('e.g. Essential logo pack'),
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: context.rh(10)),
            ShadInputFormField(
              id: '${draft.tier.name}-desc',
              controller: draft.description,
              label: const Text('What\'s included (optional)'),
              placeholder: const Text('1 concept, source file, ...'),
              maxLines: 2,
            ),
            SizedBox(height: context.rh(10)),
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
                    id: '${draft.tier.name}-delivery',
                    controller: draft.deliveryDays,
                    label: RequiredLabel('Delivery (days)'),
                    placeholder: const Text('3'),
                    keyboardType: TextInputType.number,
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
          ],
        ],
      ),
    );
  }

  // Step 4: review ------------------------------------------------

  Widget _buildReviewStep() {
    final enabled = _enabledPackages;
    final cheapest = enabled
        .map((p) => double.tryParse(p.price.text.trim()) ?? 0)
        .where((v) => v > 0)
        .toList();
    final startingPrice = cheapest.isEmpty
        ? 0
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
        SizedBox(height: context.rh(10)),
        for (final p in enabled)
          _reviewRow(
            '${p.tier.displayName} package',
            '${p.name.text.trim()} — '
            '${formatGhs(double.tryParse(p.price.text.trim()) ?? 0)}, '
            '${p.deliveryDays.text.trim()}-day delivery',
          ),
      ],
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
