import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../providers/verification_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/required_label.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/verification_badge.dart';

class SellerProfileVerificationScreen extends ConsumerStatefulWidget {
  const SellerProfileVerificationScreen({super.key});

  @override
  ConsumerState<SellerProfileVerificationScreen> createState() =>
      _SellerProfileVerificationScreenState();
}

class _SellerProfileVerificationScreenState
    extends ConsumerState<SellerProfileVerificationScreen> {
  int _currentStep = 0;
  static const int _totalSteps = 4;

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

  late final VerificationProvider _vProv;

  @override
  void initState() {
    super.initState();
    _vProv = ref.read(verificationProvider);
    _residentialAddressController.addListener(_onTextChanged);
    _digitalAddressController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vProv.loadLatestVerification();
      // When admin approves via seller_verifications OR directly toggles
      // is_verified on the users table, reload the auth profile so the
      // badge appears immediately everywhere in the app.
      _vProv.onVerificationApproved = () {
        ref.read(authProvider).loadUserProfile();
      };
      // When admin revokes, reload so the badge disappears immediately.
      _vProv.onVerificationRevoked = () {
        ref.read(authProvider).loadUserProfile();
      };
    });
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _residentialAddressController.dispose();
    _digitalAddressController.dispose();
    _videoController?.dispose();
    // Clear callbacks so they aren't called after the widget is gone.
    _vProv.onVerificationApproved = null;
    _vProv.onVerificationRevoked = null;
    super.dispose();
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

    _videoController?.dispose(); // ignore: unawaited_futures
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

    _videoController?.dispose(); // ignore: unawaited_futures
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

    ref.read(verificationProvider).submitVerificationInBackground(
      dateOfBirth: dob,
      yearOfEntrance: yoe,
      graduationYear: gy,
      residentialAddress: addr,
      digitalAddress: daddr,
      studentIdFront: front,
      studentIdBack: back,
      liveVideo: video,
    ).then((_) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            backgroundColor: AppTheme.successMoss,
            title: Text('Verification submitted! We\'ll review it shortly.'),
          ),
        );
      }
    }).catchError((e) { // ignore: unawaited_futures
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Upload failed: ${e.toString()}'),
          ),
        );
      }
    });
  }

  Future<void> _cancelVerification() async {
    final latestV = ref.read(verificationProvider).latestVerification;
    if (latestV == null) return;

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

    if (confirmed == true) {
      try {
        await ref.read(verificationProvider).cancelVerification(latestV.id);
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(
              backgroundColor: AppTheme.successMoss,
              title: Text('Verification cancelled'),
            ),
          );
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
    final prov = ref.watch(verificationProvider);

    if (prov.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + kToolbarHeight + 24,
            24,
            24,
          ),
          child: const ListSkeleton(count: 6),
        ),
      );
    }

    final authUser = ref.watch(authProvider).user;

    // Show status view if:
    // 1. Upload is in progress
    // 2. There's a pending/approved seller_verifications record
    // 3. Admin directly toggled is_verified on the users table (no record needed)
    if (prov.isUploadingBackground ||
        (authUser?.isVerified == true) ||
        (prov.latestVerification != null &&
            (prov.latestVerification!.isPending ||
                prov.latestVerification!.isApproved))) {
      return _buildStatusView();
    }

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppTheme.glassAppBar(context: context,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Seller Verification',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.charcoalInk,
              ),
            ),
            Text(
              'Step ${_currentStep + 1} of $_totalSteps',
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                color: AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.of(context).padding.top + kToolbarHeight + 16,
          16,
          MediaQuery.of(context).padding.bottom + 90,
        ),
        child: _buildCurrentStep(),
      ),
      bottomNavigationBar: _buildNavigationButtons(),
    );
  }

  // ─── Status View (for pending/approved) ────────────────────────

  Widget _buildStatusView() {
    final prov = ref.watch(verificationProvider);

    // While background upload is running and no DB record exists yet
    if (prov.isUploadingBackground && prov.latestVerification == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            16,
            16,
          ),
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

    // Admin has verified the user — always show "Verified" regardless of
    // the seller_verifications record status (which may be revoked).
    final authUser = ref.watch(authProvider).user;
    if (authUser?.isVerified == true) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            context.rw(16),
            MediaQuery.of(context).padding.top + kToolbarHeight + context.rh(16),
            context.rw(16),
            context.rh(16),
          ),
          children: [
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
                      color: AppTheme.successMoss.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: VerificationBadge(size: context.ri(48)),
                  ),
                  SizedBox(height: context.rh(16)),
                  Text(
                    'Verified',
                    style: TextStyle(
                      fontSize: context.rsp(22),
                      fontWeight: FontWeight.bold,
                      color: AppTheme.successMoss,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your seller profile is verified. Buyers can see your verified badge.',
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

    final v = prov.latestVerification!;
    final isPending = v.isPending;
    final isApproved = v.isApproved;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Seller Verification')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.rw(16),
          MediaQuery.of(context).padding.top + kToolbarHeight + context.rh(16),
          context.rw(16),
          context.rh(16),
        ),
        children: [
          if (prov.isUploadingBackground) ...[
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
          RequiredLabel(
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
          RequiredLabel(
            'Year of Entrance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _yearOfEntrance,
            borderRadius: BorderRadius.circular(18),
            dropdownColor: AppTheme.pureSurface,
            menuMaxHeight: 320,
            itemHeight: AppTheme.minTapTarget,
            icon: const Icon(LucideIcons.chevronDown, size: 18, color: AppTheme.mutedSteel),
            style: const TextStyle(fontSize: 15, color: AppTheme.charcoalInk),
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
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
          RequiredLabel(
            'Expected Graduation Year',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _graduationYear,
            borderRadius: BorderRadius.circular(18),
            dropdownColor: AppTheme.pureSurface,
            menuMaxHeight: 320,
            itemHeight: AppTheme.minTapTarget,
            icon: const Icon(LucideIcons.chevronDown, size: 18, color: AppTheme.mutedSteel),
            style: const TextStyle(fontSize: 15, color: AppTheme.charcoalInk),
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
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
          RequiredLabel(
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
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toUpperCase()),
              ),
            ],
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
        RequiredLabel(
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
        RequiredLabel(
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
        RequiredLabel(
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
    final prov = ref.watch(verificationProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        0,
        10,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: AppTheme.frosted(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        enabled: _agreedToTerms,
                        onPressed: (_agreedToTerms && !prov.isUploadingBackground)
                            ? _submitVerification
                            : null,
                        child: prov.isUploadingBackground
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
                        enabled: _canProceed(),
                        onPressed: _canProceed() ? () => setState(() => _currentStep++) : null,
                        child: const Text('Continue'),
                      ),
              ),
            ],
          ),
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
