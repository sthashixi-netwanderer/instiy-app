import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../config/app_theme.dart';
import '../../services/verification_service.dart';
import '../../models/seller_verification_model.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/verification_badge.dart';

class SellerProfileVerificationScreen extends StatefulWidget {
  const SellerProfileVerificationScreen({super.key});

  @override
  State<SellerProfileVerificationScreen> createState() =>
      _SellerProfileVerificationScreenState();
}

class _SellerProfileVerificationScreenState
    extends State<SellerProfileVerificationScreen> {
  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isUploadingBackground = false;
  bool _isLoading = true;
  SellerVerification? _existingVerification;

  // Form keys for each step
  final _formKeyStep0 = GlobalKey<FormState>();

  // Step 0: Personal info
  DateTime? _dateOfBirth;
  int? _yearOfEntrance;
  int? _graduationYear;
  final _residentialAddressController = TextEditingController();
  final _digitalAddressController = TextEditingController();

  // Step 1: Student ID
  File? _studentIdFront;
  File? _studentIdBack;

  // Step 2: Video
  File? _liveVideo;
  VideoPlayerController? _videoController;
  Duration _videoDuration = Duration.zero;

  // Step 3: Terms
  bool _agreedToTerms = false;

  final _imagePicker = ImagePicker();

  static const int _minVideoSeconds = 10;
  static const int _currentYear = 2026;

  @override
  void initState() {
    super.initState();
    _residentialAddressController.addListener(_onTextChanged);
    _digitalAddressController.addListener(_onTextChanged);
    _loadExistingVerification();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _residentialAddressController.dispose();
    _digitalAddressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadExistingVerification() async {
    try {
      final verification =
          await VerificationService.getLatestVerification();
      if (mounted) {
        setState(() {
          _existingVerification = verification;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ─── Image/Video Picking ───────────────────────────────────────

  Future<void> _pickStudentIdFront() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _studentIdFront = File(picked.path));
  }

  Future<void> _pickStudentIdFrontGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _studentIdFront = File(picked.path));
  }

  Future<void> _pickStudentIdBack() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _studentIdBack = File(picked.path));
  }

  Future<void> _pickStudentIdBackGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _studentIdBack = File(picked.path));
  }

  Future<void> _recordVideo() async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxDuration: const Duration(seconds: 15),
    );
    if (picked == null) return;

    final file = File(picked.path);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();

    final duration = controller.value.duration;
    if (duration.inSeconds < _minVideoSeconds) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Video must be at least $_minVideoSeconds seconds. '
                'Recorded ${duration.inSeconds}s.'),
          ),
        );
      }
      await controller.dispose();
      return;
    }

    _videoController?.dispose();
    setState(() {
      _liveVideo = file;
      _videoController = controller;
      _videoDuration = duration;
    });
  }

  Future<void> _pickVideoFromGallery() async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 15),
    );
    if (picked == null) return;

    final file = File(picked.path);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();

    final duration = controller.value.duration;
    if (duration.inSeconds < _minVideoSeconds) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Video must be at least $_minVideoSeconds seconds. '
                'Selected video is ${duration.inSeconds}s.'),
          ),
        );
      }
      await controller.dispose();
      return;
    }

    _videoController?.dispose();
    setState(() {
      _liveVideo = file;
      _videoController = controller;
      _videoDuration = duration;
    });
  }

  // ─── Date Picker ───────────────────────────────────────────────

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2002, 1, 1),
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year - 15),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppTheme.accent,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  // ─── Submit ────────────────────────────────────────────────────

  Future<void> _submitVerification() async {
    if (_dateOfBirth == null ||
        _yearOfEntrance == null ||
        _graduationYear == null ||
        _residentialAddressController.text.trim().isEmpty ||
        _studentIdFront == null ||
        _studentIdBack == null ||
        _liveVideo == null) {
      ShadToaster.of(context).show(
        const ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Please complete all fields'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _isUploadingBackground = true;
    });

    // Show uploading toast
    if (mounted) {
      ShadToaster.of(context).show(
        const ShadToast(
          backgroundColor: AppTheme.accent,
          title: Text('Uploading verification...'),
        ),
      );
    }

    // Snapshot the data we need before navigating away
    final dob = _dateOfBirth!;
    final yoe = _yearOfEntrance!;
    final gy = _graduationYear!;
    final addr = _residentialAddressController.text.trim();
    final daddr = _digitalAddressController.text.trim().isEmpty
        ? null
        : _digitalAddressController.text.trim();
    final front = _studentIdFront!;
    final back = _studentIdBack!;
    final video = _liveVideo!;

    // Return user to status view immediately
    setState(() {
      _currentStep = 0;
      _isSubmitting = false;
    });

    // Fire upload in background — no await
    _uploadInBackground(
      dateOfBirth: dob,
      yearOfEntrance: yoe,
      graduationYear: gy,
      residentialAddress: addr,
      digitalAddress: daddr,
      studentIdFront: front,
      studentIdBack: back,
      liveVideo: video,
    );
  }

  Future<void> _uploadInBackground({
    required DateTime dateOfBirth,
    required int yearOfEntrance,
    required int graduationYear,
    required String residentialAddress,
    String? digitalAddress,
    required File studentIdFront,
    required File studentIdBack,
    required File liveVideo,
  }) async {
    try {
      await VerificationService.submitVerification(
        dateOfBirth: dateOfBirth,
        yearOfEntrance: yearOfEntrance,
        graduationYear: graduationYear,
        residentialAddress: residentialAddress,
        digitalAddress: digitalAddress,
        studentIdFront: studentIdFront,
        studentIdBack: studentIdBack,
        liveVideo: liveVideo,
      );

      if (mounted) {
        setState(() => _isUploadingBackground = false);
        ShadToaster.of(context).show(
          const ShadToast(
            backgroundColor: AppTheme.successMoss,
            title: Text('Verification submitted! We\'ll review it shortly.'),
          ),
        );
        await _loadExistingVerification();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingBackground = false);
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Upload failed: ${e.toString()}'),
          ),
        );
      }
    }
  }

  Future<void> _cancelVerification() async {
    if (_existingVerification == null) return;

final confirmed = await AppTheme.showGlassDialog<bool>(
  context: context,
  title: const Text('Cancel Verification'),
  description: const Text(
      'Are you sure you want to cancel your verification request?'),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(false),
      child: const Text('No'),
    ),
    ShadButton.destructive(
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text('Yes, Cancel'),
    ),
  ],
);

    if (confirmed == true && _existingVerification != null) {
      try {
        await VerificationService.cancelVerification(_existingVerification!.id);
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(
              backgroundColor: AppTheme.successMoss,
              title: Text('Verification cancelled'),
            ),
          );
          await _loadExistingVerification();
        }
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast(
              backgroundColor: AppTheme.destructive,
              title: Text(e.toString()),
            ),
          );
        }
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: ListSkeleton(count: 6),
        ),
      );
    }

    // Show existing verification status if pending/approved
    if (_isUploadingBackground ||
        (_existingVerification != null &&
            (_existingVerification!.isPending ||
                _existingVerification!.isApproved))) {
      return _buildStatusView();
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context,
        title: const Text('Seller Verification'),
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCurrentStep(),
            ),
          ),
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  // ─── Status View (for pending/approved) ────────────────────────

  Widget _buildStatusView() {
    // While background upload is running and no DB record exists yet
    if (_isUploadingBackground && _existingVerification == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Column(
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Uploading your documents...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please don\'t close this screen. Your verification is being submitted.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final v = _existingVerification!;
    final isPending = v.isPending;
    final isApproved = v.isApproved;

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
      body: ListView(
        padding: context.rAll(16),
        children: [
          if (_isUploadingBackground) ...[
            Container(
              padding: context.rAll(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(context.rr(12)),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: context.rw(18),
                    height: context.rh(18),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Text(
                      'Uploading your documents... You can close this screen.',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w500,
                        fontSize: context.rsp(13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.rh(16)),
          ],
          Container(
            padding: context.rAll(24),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(20)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Column(
              children: [
                Container(
                  width: context.rw(80),
                  height: context.rh(80),
                  decoration: BoxDecoration(
                    color: (isApproved
                            ? AppTheme.successMoss
                            : AppTheme.warningAmber)
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: isApproved
                      ? VerificationBadge(size: context.ri(48))
                      : Icon(
                          LucideIcons.clock,
                          size: context.ri(40),
                          color: AppTheme.warningAmber,
                        ),
                ),
                SizedBox(height: context.rh(16)),
                Text(
                  v.statusDisplayName,
                  style: TextStyle(
                    fontSize: context.rsp(22),
                    fontWeight: FontWeight.bold,
                    color: isApproved
                        ? AppTheme.successMoss
                        : AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isApproved
                      ? 'Your seller profile is verified. Buyers can see your verified badge.'
                      : 'Your verification is being reviewed by our team. This usually takes 1-2 business days.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.mutedSteel,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(16)),
          // Details card
          Container(
            padding: context.rAll(16),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(16)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submission Details',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(12)),
                _detailRow('Date of Birth',
                    DateFormat('dd MMM yyyy').format(v.dateOfBirth)),
                _detailRow('Year of Entrance', '${v.yearOfEntrance}'),
                _detailRow('Graduation Year', '${v.graduationYear}'),
                _detailRow('Residential Address', v.residentialAddress),
                if (v.digitalAddress != null && v.digitalAddress!.isNotEmpty)
                  _detailRow('Digital Address', v.digitalAddress!),
                _detailRow(
                    'Submitted', DateFormat('dd MMM yyyy').format(v.createdAt)),
                if (v.adminNotes != null && v.adminNotes!.isNotEmpty) ...[
                  SizedBox(height: context.rh(8)),
                  Container(
                    padding: context.rAll(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warningAmber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(context.rr(8)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.messageSquare,
                            size: context.ri(14), color: AppTheme.warningAmber),
                        SizedBox(width: context.rw(8)),
                        Expanded(
                          child: Text(
                            v.adminNotes!,
                            style: TextStyle(
                              fontSize: context.rsp(13),
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isPending) ...[
            SizedBox(height: context.rh(16)),
            SizedBox(
              width: double.infinity,
              child: ShadButton.destructive(
                onPressed: _cancelVerification,
                child: const Text('Cancel Request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.mutedSteel, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step Indicator ────────────────────────────────────────────

  Widget _buildStepIndicator() {
    final steps = ['Personal Info', 'Student ID', 'Video', 'Review'];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(12)),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        border: Border(bottom: BorderSide(color: AppTheme.whisperBorder)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(steps.length, (index) {
            final isActive = index == _currentStep;
            final isDone = index < _currentStep;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: context.rw(28),
                  height: context.rh(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? AppTheme.successMoss
                        : isActive
                            ? AppTheme.accent
                            : AppTheme.warmMist,
                    border: Border.all(
                      color: isDone
                          ? AppTheme.successMoss
                          : isActive
                              ? AppTheme.accent
                              : AppTheme.whisperBorder,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? Icon(LucideIcons.check, size: context.ri(14), color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: context.rsp(12),
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : AppTheme.mutedSteel,
                            ),
                          ),
                  ),
                ),
                if (index < steps.length - 1)
                  Container(
                    width: context.rw(32),
                    height: context.rh(2),
                    margin: EdgeInsets.symmetric(horizontal: context.rw(4)),
                    color: isDone ? AppTheme.successMoss : AppTheme.whisperBorder,
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ─── Step Builders ─────────────────────────────────────────────

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep0PersonalInfo();
      case 1:
        return _buildStep1StudentId();
      case 2:
        return _buildStep2Video();
      case 3:
        return _buildStep3Review();
      default:
        return const SizedBox.shrink();
    }
  }

  // Step 0: Personal Information
  Widget _buildStep0PersonalInfo() {
    return Form(
      key: _formKeyStep0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Provide your student details for verification.',
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
          const SizedBox(height: 24),

          // Date of Birth
          const Text(
            'Date of Birth',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDateOfBirth,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 18, color: AppTheme.mutedSteel),
                  const SizedBox(width: 12),
                  Text(
                    _dateOfBirth != null
                        ? DateFormat('dd MMMM yyyy').format(_dateOfBirth!)
                        : 'Select your date of birth',
                    style: TextStyle(
                      color: _dateOfBirth != null
                          ? AppTheme.charcoalInk
                          : AppTheme.mutedSteel,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Year of Entrance
          const Text(
            'Year of Entrance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _yearOfEntrance,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.whisperBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.whisperBorder),
              ),
              filled: true,
              fillColor: AppTheme.pureSurface,
            ),
            hint: const Text('Select year'),
            items: List.generate(
              20,
              (i) => DropdownMenuItem(
                value: _currentYear - i,
                child: Text('${_currentYear - i}'),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _yearOfEntrance = val;
                if (val != null && _graduationYear != null && _graduationYear! <= val) {
                  _graduationYear = null;
                }
              });
            },
          ),
          const SizedBox(height: 20),

          // Graduation Year
          const Text(
            'Expected Graduation Year',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _graduationYear,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.whisperBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.whisperBorder),
              ),
              filled: true,
              fillColor: AppTheme.pureSurface,
            ),
            hint: _yearOfEntrance != null
                ? Text('From ${_yearOfEntrance! + 1}')
                : const Text('Select year'),
            items: List.generate(
              15,
              (i) {
                final startYear = _yearOfEntrance != null
                    ? (_yearOfEntrance! + 1)
                    : _currentYear;
                return DropdownMenuItem(
                  value: startYear + i,
                  child: Text('${startYear + i}'),
                );
              },
            ),
            onChanged: (val) => setState(() => _graduationYear = val),
          ),
          const SizedBox(height: 20),

          // Residential Address
          const Text(
            'Residential Address',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          ShadInput(
            controller: _residentialAddressController,
            placeholder: const Text('e.g. Hall 5, Room 23, KNUST'),
          ),
          const SizedBox(height: 20),

          // Digital Address
          const Text(
            'Digital Address (Preferred)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          ShadInput(
            controller: _digitalAddressController,
            placeholder: const Text('e.g. GA-123-4567'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Digital address helps us verify your location quickly. '
                    'You can get yours from the Ghana Post GPS app.',
                    style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: Student ID
  Widget _buildStep1StudentId() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Student ID Card',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload clear photos of the front and back of your student ID.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),

        // Front
        const Text(
          'Front of Student ID',
          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          image: _studentIdFront,
          onCamera: _pickStudentIdFront,
          onGallery: _pickStudentIdFrontGallery,
          label: 'Tap to capture front',
        ),
        const SizedBox(height: 20),

        // Back
        const Text(
          'Back of Student ID',
          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          image: _studentIdBack,
          onCamera: _pickStudentIdBack,
          onGallery: _pickStudentIdBackGallery,
          label: 'Tap to capture back',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: AppTheme.warningAmber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ensure all text and your photo on the ID are clearly visible. '
                  'Avoid glare and blur.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker({
    required File? image,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => _showImageSourceDialog(onCamera, onGallery),
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: image != null ? AppTheme.successMoss : AppTheme.whisperBorder,
            width: image != null ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(image, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        if (image == _studentIdFront) {
                          _studentIdFront = null;
                        } else {
                          _studentIdBack = null;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.camera, size: 40, color: AppTheme.mutedSteel),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(color: AppTheme.mutedSteel),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'or choose from gallery',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }

  void _showImageSourceDialog(VoidCallback onCamera, VoidCallback onGallery) {
AppTheme.showGlassDialog(
  context: context,
  title: const Text('Choose Source'),
  child: Material(
    type: MaterialType.transparency,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(LucideIcons.camera),
          title: const Text('Camera'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () {
            Navigator.of(context).pop();
            onCamera();
          },
        ),
        ListTile(
          leading: const Icon(LucideIcons.image),
          title: const Text('Gallery'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () {
            Navigator.of(context).pop();
            onGallery();
          },
        ),
      ],
    ),
  ),
);
  }

  // Step 2: Video Verification
  Widget _buildStep2Video() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Video Verification',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Record a short video of yourself holding your student ID. '
          'This helps us confirm your identity.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),

        if (_liveVideo != null && _videoController != null) ...[
          // Video preview
          Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.successMoss, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_videoController!),
                if (!_videoController!.value.isPlaying)
                  GestureDetector(
                    onTap: () {
                      _videoController!.play();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.play,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                if (_videoController!.value.isPlaying)
                  GestureDetector(
                    onTap: () {
                      _videoController!.pause();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.pause,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_videoDuration.inSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _recordVideo,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Re-record'),
                ),
              ),
            ],
          ),
        ] else ...[
          // Recording prompt
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.whisperBorder,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.video,
                    size: 40,
                    color: AppTheme.destructive,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Record a $_minVideoSeconds+ second video',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hold your student ID next to your face.\n'
                  'Speak your name and student ID number.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton(
                        onPressed: _recordVideo,
                        leading: const Icon(LucideIcons.camera, size: 18),
                        child: const Text('Record Video'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ShadButton.outline(
                        onPressed: _pickVideoFromGallery,
                        leading: const Icon(LucideIcons.upload, size: 18),
                        child: const Text('Upload'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.lightbulb, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tips: Use good lighting, look directly at the camera, '
                  'and clearly show your student ID.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Step 3: Review & Submit
  Widget _buildStep3Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review & Submit',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Please review your information before submitting.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),

        // Info summary
        _reviewSection('Personal Information', [
          _reviewItem('Date of Birth',
              _dateOfBirth != null ? DateFormat('dd MMM yyyy').format(_dateOfBirth!) : ''),
          _reviewItem('Year of Entrance', '${_yearOfEntrance ?? ''}'),
          _reviewItem('Graduation Year', '${_graduationYear ?? ''}'),
          _reviewItem('Residential Address', _residentialAddressController.text),
          if (_digitalAddressController.text.isNotEmpty)
            _reviewItem('Digital Address', _digitalAddressController.text),
        ]),
        const SizedBox(height: 16),

        _reviewSection('Documents', [
          _reviewFileItem('Student ID (Front)', _studentIdFront),
          _reviewFileItem('Student ID (Back)', _studentIdBack),
          _reviewFileItem(
              'Video (${_videoDuration.inSeconds}s)', _liveVideo),
        ]),
        const SizedBox(height: 24),

        // Terms checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreedToTerms,
              onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
              activeColor: AppTheme.accent,
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'I confirm that all information provided is accurate and the documents are genuine. '
                  'I understand that providing false information may result in account suspension.',
                  style: TextStyle(fontSize: 13, color: AppTheme.mutedSteel, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reviewSection(String title, List<Widget> children) {
    return Container(
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
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _reviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.mutedSteel),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewFileItem(String label, File? file) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            file != null ? LucideIcons.checkCircle : LucideIcons.xCircle,
            size: 16,
            color: file != null ? AppTheme.successMoss : AppTheme.destructive,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.mutedSteel),
          ),
        ],
      ),
    );
  }

  // ─── Navigation Buttons ────────────────────────────────────────

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => setState(() => _currentStep--),
                  child: const Text('Back'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _currentStep == 3
                  ? ShadButton(
                      onPressed: (_agreedToTerms && !_isSubmitting)
                          ? _submitVerification
                          : null,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit Verification'),
                    )
                  : ShadButton(
                      onPressed: _canProceed() ? () => setState(() => _currentStep++) : null,
                      child: const Text('Continue'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _dateOfBirth != null &&
            _yearOfEntrance != null &&
            _graduationYear != null &&
            _graduationYear! > _yearOfEntrance! &&
            _residentialAddressController.text.trim().isNotEmpty;
      case 1:
        return _studentIdFront != null && _studentIdBack != null;
      case 2:
        return _liveVideo != null;
      default:
        return true;
    }
  }
}
