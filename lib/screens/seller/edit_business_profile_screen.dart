import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;

import '../../config/app_theme.dart';
import '../../models/business_profile_model.dart';
import '../../models/picked_media.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';
import '../../services/business_profile_service.dart';
import '../../services/storage_service.dart';
import '../../services/sms_service.dart';

import '../../utils/responsive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/supabase_service.dart';
import '../../widgets/image_picker_sheet.dart';
import '../../widgets/skeleton.dart';

class EditBusinessProfileScreen extends ConsumerStatefulWidget {
  final BusinessProfile? existingProfile;

  const EditBusinessProfileScreen({super.key, this.existingProfile});

  @override
  ConsumerState<EditBusinessProfileScreen> createState() => _EditBusinessProfileScreenState();
}

class _EditBusinessProfileScreenState extends ConsumerState<EditBusinessProfileScreen> {
  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationUrlController = TextEditingController();
  final _digitalAddressController = TextEditingController();
  dynamic _bannerFile;
  String? _existingBannerUrl;
  List<StorePhoneNumber> _phoneNumbers = [];
  bool _qrCodePublic = false;
  bool _isPreview = false;
  bool _isSaving = false;
  bool _isLoading = true;

  bool _isLookingUpAddress = false;
  String? _resolvedDetails;
  String? _gpsApiUrl;
  String? _gpsApiToken;

  @override
  void initState() {
    super.initState();
    _businessNameController.addListener(_onTextChanged);
    _descriptionController.addListener(_onTextChanged);
    _locationUrlController.addListener(_onTextChanged);
    _digitalAddressController.addListener(_onTextChanged);
    _loadProfile();
    _loadGPSConfig();
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _isFormValid => _businessNameController.text.trim().isNotEmpty;

  Future<void> _loadGPSConfig() async {
    try {
      final res = await SupabaseService.table('ghanapost_config').select();
      for (final item in res) {
        if (item['key'] == 'api_url') {
          _gpsApiUrl = item['value'] as String;
        } else if (item['key'] == 'api_token') {
          _gpsApiToken = item['value'] as String;
        }
      }
    } catch (e) {
      debugPrint('Error loading GPS config: $e');
    }
  }

  Future<void> _lookupAddress() async {
    final address = _digitalAddressController.text.trim().toUpperCase();
    if (address.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          backgroundColor: Colors.red,
          title: Text('Please enter a digital address first.'),
        ),
      );
      return;
    }

    setState(() {
      _isLookingUpAddress = true;
      _resolvedDetails = null;
    });

    try {
      if (_gpsApiUrl == null) {
        await _loadGPSConfig();
      }

      // Validate the API URL to prevent URL injection from a compromised DB record.
      // Only allow https:// URLs; fall back to the known-good default if invalid.
      const fallbackGpsUrl = 'https://mijoride.ghanapostgps.com/user/get_address';
      final rawUrl = _gpsApiUrl ?? fallbackGpsUrl;
      final validatedUri = Uri.tryParse(rawUrl);
      final url = (validatedUri != null && validatedUri.scheme == 'https')
          ? rawUrl
          : fallbackGpsUrl;
      // No hardcoded fallback token — if not loaded, the request will fail
      // gracefully with a 401 rather than using a leaked credential.
      final token = _gpsApiToken ?? '';

      // Use Uri.replace to safely encode the address parameter (prevents query-string injection).
      final uri = Uri.parse(url).replace(
        queryParameters: {'address': address},
      );
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          final result = (data['Result'] is Map)
              ? data['Result'] as Map<String, dynamic>
              : (data['result'] is Map)
                  ? data['result'] as Map<String, dynamic>
                  : data as Map<String, dynamic>;

          if (result['GPSName'] != null || result['CenterLatitude'] != null) {
            final double? lat = result['CenterLatitude'] != null ? double.tryParse(result['CenterLatitude'].toString()) : null;
            final double? lng = result['CenterLongitude'] != null ? double.tryParse(result['CenterLongitude'].toString()) : null;

            if (lat != null && lng != null) {
              final street = result['Street'] ?? '';
              final region = result['Region'] ?? '';
              final district = result['District'] ?? '';
              final community = result['Community'] ?? '';

              final breakdown = [
                if (street.toString().isNotEmpty) 'Street: $street',
                if (community.toString().isNotEmpty) 'Community: $community',
                if (district.toString().isNotEmpty) 'District: $district',
                if (region.toString().isNotEmpty) 'Region: $region',
              ].join(', ');

              setState(() {
                _locationUrlController.text = 'https://maps.google.com/maps?q=$lat,$lng&t=&z=15&ie=UTF8&iwloc=&output=embed';
                _resolvedDetails = breakdown.isNotEmpty ? breakdown : 'Coordinates resolved: ($lat, $lng)';
              });

              if (!mounted) return;
              ShadToaster.of(context).show(
                const ShadToast(title: Text('Digital address resolved successfully!')),
              );
            } else {
              throw Exception('CenterLatitude or CenterLongitude missing from response.');
            }
          } else {
            throw Exception(data['Message'] ?? data['message'] ?? 'Could not resolve digital address.');
          }
        } else {
          throw Exception('Empty response body.');
        }
      } else {
        throw Exception('API responded with status code ${response.statusCode}');
      }
    } catch (e) {
      // Log the full error internally; show a generic message to the user to
      // avoid leaking internal API error details or stack traces.
      debugPrint('Error looking up address: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Could not resolve the digital address. Please check it and try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUpAddress = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    BusinessProfile? profile = widget.existingProfile;
    profile ??= await BusinessProfileService.getProfile(user.id);

    if (!mounted) return;

    if (profile != null) {
      _businessNameController.text = profile.businessName ?? user.fullName;
      _descriptionController.text = profile.description ?? '';
      _locationUrlController.text = profile.locationUrl ?? '';
      _digitalAddressController.text = (profile.digitalAddress ?? '').toUpperCase();
      _existingBannerUrl = profile.bannerUrl;
      _phoneNumbers = List.from(profile.phoneNumbers);
      _qrCodePublic = profile.qrCodePublic;
    } else {
      _businessNameController.text = user.fullName;
      // Add registration phone if available
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        _phoneNumbers.add(StorePhoneNumber(
          number: user.phoneNumber!,
          label: 'Primary',
          isWhatsApp: true,
        ));
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    _locationUrlController.dispose();
    _digitalAddressController.dispose();
    super.dispose();
  }

  Future<void> _pickBanner() async {
    final file = await ImagePickerSheet.pickSingle(context);
    if (file != null) {
      setState(() => _bannerFile = file);
    }
  }

  void _addPhoneNumber() {
    final numberController = TextEditingController();
    final labelController = TextEditingController(text: 'Mobile');

    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Add Phone Number'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: numberController,
              placeholder: const Text('Phone number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ShadInput(
              controller: labelController,
              placeholder: const Text('Label (e.g., Mobile, Office)'),
            ),
          ],
        ),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AnimatedBuilder(
          animation: numberController,
          builder: (context, _) {
            final canAdd = numberController.text.trim().isNotEmpty;
            return ShadButton(
              enabled: canAdd,
              onPressed: canAdd
                  ? () {
                      final number = numberController.text.trim();
                      final label = labelController.text.trim().isEmpty
                          ? 'Mobile'
                          : labelController.text.trim();
                      Navigator.of(context).pop();
                      if (number.isNotEmpty) {
                        _verifyAndAddNumber(number, label);
                      }
                    }
                  : null,
              child: const Text('Verify & Add'),
            );
          },
        ),
      ],
    );
  }

  Future<void> _verifyAndAddNumber(String number, String label) async {
    // Check if number already exists in this profile
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (_phoneNumbers.any((p) => p.number.replaceAll(RegExp(r'[^\d+]'), '') == cleaned)) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('This number is already added'),
          ),
        );
      }
      return;
    }

    // Check if phone is already taken by any user across the platform
    final userId = SupabaseService.auth.currentUser?.id;
    final taken = await AuthService.isPhoneTaken(number, excludeUserId: userId);
    if (taken) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('This phone number is already registered to another account'),
          ),
        );
      }
      return;
    }

    final otp = (100000 + Random().nextInt(900000)).toString();

    // Send OTP
    setState(() {});
    final sent = await SmsService.sendOtp(to: number, otp: otp);

    if (!sent) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: const Text('Failed to send verification code. Try again.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show OTP verification dialog
    _showOtpDialog(otp, number, label);
  }

  void _showOtpDialog(String correctOtp, String number, String label) {
    final otpController = TextEditingController();
    String? otpError;
    bool isVerifying = false;

    AppTheme.showGlassDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text(
              'Verify Phone Number',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit code sent to $number',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.mutedSteel,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ShadInput(
              controller: otpController,
              placeholder: const Text('6-digit code'),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            if (otpError != null) ...[
              const SizedBox(height: 8),
              Text(
                otpError!,
                style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.ghost(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: otpController,
                  builder: (context, _) {
                    final codeValid = otpController.text.trim().length == 6;
                    return ShadButton(
                      enabled: codeValid,
                      onPressed: (codeValid && !isVerifying)
                          ? () async {
                              final input = otpController.text.trim();
                              if (input.length != 6) {
                                setDialogState(() => otpError = 'Enter a valid 6-digit code');
                                return;
                              }
                              if (input != correctOtp) {
                                setDialogState(() => otpError = 'Incorrect code. Try again.');
                                return;
                              }

                              setDialogState(() {
                                isVerifying = true;
                                otpError = null;
                              });

                              // Add the verified number
                              setState(() {
                                _phoneNumbers.add(StorePhoneNumber(
                                  number: number,
                                  label: label,
                                ));
                              });

                              Navigator.of(ctx).pop();
                              if (mounted) {
                                ShadToaster.of(context).show(
                                  const ShadToast(
                                    title: Text('Phone number verified and added!'),
                                  ),
                                );
                              }
                            }
                          : null,
                      child: isVerifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _removePhoneNumber(int index) {
    if (_phoneNumbers.length <= 1) return;
    setState(() => _phoneNumbers.removeAt(index));
  }

  void _toggleWhatsApp(int index) {
    setState(() {
      for (int i = 0; i < _phoneNumbers.length; i++) {
        final phone = _phoneNumbers[i];
        _phoneNumbers[i] = StorePhoneNumber(
          number: phone.number,
          label: phone.label,
          isWhatsApp: i == index ? !phone.isWhatsApp : false,
        );
      }
    });
  }

  void _showMarkdownHelp() {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Formatting Guide'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use these formatting options in your description:',
            style: TextStyle(color: AppTheme.mutedSteel, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _helpRow('**bold text**', '**bold text**'),
          _helpRow('*italic text*', '*italic text*'),
          _helpRow('# Heading 1', '# Big heading'),
          _helpRow('## Heading 2', '## Medium heading'),
          _helpRow('### Heading 3', '### Small heading'),
          _helpRow('- List item', '- Bullet list'),
          _helpRow('1. Numbered item', '1. Numbered list'),
          _helpRow('> Quote', '> Blockquote'),
          _helpRow('---', '--- (horizontal line)'),
          _helpRow('[link text](url)', '[Click here](https://...)'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.lightbulb, size: 14, color: AppTheme.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Use the Preview button to see how your description will look.',
                    style: TextStyle(fontSize: 12, color: AppTheme.charcoalInk),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          size: ShadButtonSize.sm,
          child: const Text('Got it'),
        ),
      ],
    );
  }

  Widget _helpRow(String syntax, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              syntax,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppTheme.charcoalInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String? bannerUrl = _existingBannerUrl;

      // Upload new banner if picked
      if (_bannerFile != null) {
        // Delete old banner if exists
        if (_existingBannerUrl != null) {
          try {
            await StorageService.deleteImage(_existingBannerUrl!);
          } catch (_) {}
        }
        bannerUrl = await StorageService.uploadImage(
          file: _bannerFile!,
          folder: 'banners',
        );
      }

      await BusinessProfileService.upsertProfile(
        sellerId: user.id,
        bannerUrl: bannerUrl,
        businessName: _businessNameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        locationUrl: _locationUrlController.text.trim().isEmpty
            ? null
            : _locationUrlController.text.trim(),
        digitalAddress: _digitalAddressController.text.trim().isEmpty
            ? null
            : _digitalAddressController.text.trim(),
        qrCodePublic: _qrCodePublic,
        phoneNumbers: _phoneNumbers,
      );

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Business profile saved!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight;
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Business Profile')),
        body: Padding(
          padding: EdgeInsets.only(top: topPad + 16, left: 16, right: 16, bottom: 16),
          child: const ListSkeleton(count: 6),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, 
        title: const Text('Business Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ShadButton(
              enabled: _isFormValid,
              onPressed: (_isSaving || !_isFormValid) ? null : _save,
              size: ShadButtonSize.sm,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(16), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16), context.rw(16), context.rh(16)),
        children: [
          // Banner picker
          _buildBannerSection(),
          SizedBox(height: context.rh(24)),

          // Business name
          Text(
            'Business Name',
            style: TextStyle(
              fontSize: context.rsp(14),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          ShadInput(
            controller: _businessNameController,
            placeholder: const Text('Your business or store name'),
          ),
          SizedBox(height: context.rh(24)),

          // Description (Markdown editor)
          _buildDescriptionSection(),
          SizedBox(height: context.rh(24)),

          // Phone numbers
          _buildPhoneNumbersSection(),
          SizedBox(height: context.rh(24)),

          // Location
          _buildLocationSection(),
          SizedBox(height: context.rh(24)),

          // QR Code Visibility
          _buildQrCodeSection(),
          SizedBox(height: context.rh(80)),
        ],
      ),
    );
  }

  Widget _buildBannerSection() {
    return GestureDetector(
      onTap: _pickBanner,
      child: Container(
        height: context.rh(180),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.warmMist,
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: _bannerFile != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _bannerFile is PickedMedia
                      ? Image.memory((_bannerFile as PickedMedia).bytes, fit: BoxFit.cover)
                      : const SizedBox.shrink(),
                  _buildBannerOverlay(),
                ],
              )
            : _existingBannerUrl != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: _existingBannerUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        placeholder: (_, _) => Container(color: AppTheme.warmMist),
                        errorWidget: (_, _, _) => _buildBannerPlaceholder(),
                      ),
                      _buildBannerOverlay(),
                    ],
                  )
                : _buildBannerPlaceholder(),
      ),
    );
  }

  Widget _buildBannerPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.image, size: context.ri(32), color: AppTheme.accent),
        ),
        SizedBox(height: context.rh(12)),
        Text(
          'Upload Banner Image',
          style: TextStyle(
            fontSize: context.rsp(14),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(4)),
        Text(
          'Tap to select an image',
          style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
        ),
      ],
    );
  }

  Widget _buildBannerOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(8)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.camera, size: context.ri(14), color: Colors.white),
            SizedBox(width: context.rw(4)),
            Text(
              'Change Banner',
              style: TextStyle(color: Colors.white, fontSize: context.rsp(12), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Business Description',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(width: context.rw(4)),
                GestureDetector(
                  onTap: _showMarkdownHelp,
                  child: Container(
                    padding: context.rAll(2),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.info, size: context.ri(13), color: AppTheme.accent),
                  ),
                ),
              ],
            ),
            ShadButton.ghost(
              onPressed: () => setState(() => _isPreview = !_isPreview),
              size: ShadButtonSize.sm,
              leading: Icon(
                _isPreview ? LucideIcons.pencil : LucideIcons.eye,
                size: context.ri(14),
              ),
              child: Text(_isPreview ? 'Edit' : 'Preview'),
            ),
          ],
        ),
        SizedBox(height: context.rh(4)),
        Text(
          'Supports Markdown formatting (bold, italic, lists, etc.)',
          style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel),
        ),
        SizedBox(height: context.rh(8)),
        if (_isPreview)
          Container(
            constraints: BoxConstraints(minHeight: context.rh(150)),
            padding: context.rAll(16),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(12)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: _descriptionController.text.trim().isEmpty
                ? const Text(
                    'Nothing to preview yet...',
                    style: TextStyle(color: AppTheme.mutedSteel, fontStyle: FontStyle.italic),
                  )
                : MarkdownBody(
                    data: _descriptionController.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: AppTheme.charcoalInk, height: 1.5),
                      h1: TextStyle(fontSize: context.rsp(20), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
                      h2: TextStyle(fontSize: context.rsp(18), fontWeight: FontWeight.bold, color: AppTheme.charcoalInk),
                      h3: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                      listBullet: const TextStyle(color: AppTheme.charcoalInk),
                    ),
                  ),
          )
        else
          ShadInput(
            controller: _descriptionController,
            maxLines: 8,
            placeholder: const Text('Tell customers about your business, what you sell, your policies...'),
            keyboardType: TextInputType.multiline,
          ),
      ],
    );
  }

  Widget _buildPhoneNumbersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Phone Numbers',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            ShadButton.ghost(
              onPressed: _addPhoneNumber,
              size: ShadButtonSize.sm,
              leading: const Icon(LucideIcons.plus, size: 14),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Designate one number as your WhatsApp contact',
          style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 12),
        if (_phoneNumbers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No phone numbers added yet',
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
            ),
          )
        else
          ...List.generate(_phoneNumbers.length, (index) {
            final phone = _phoneNumbers[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pureSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.whisperBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: phone.isWhatsApp
                          ? const Color(0xFF25D366).withValues(alpha: 0.1)
                          : AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: phone.isWhatsApp
                        ? SvgPicture.asset(
                            'assets/whatsapp-svgrepo-com.svg',
                            width: 16,
                            height: 16,
                          )
                        : const Icon(LucideIcons.phone, size: 16, color: AppTheme.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phone.number,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              phone.label,
                              style: const TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                            ),
                            if (phone.isWhatsApp) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'WhatsApp',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF25D366),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // WhatsApp toggle
                  GestureDetector(
                    onTap: () => _toggleWhatsApp(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: phone.isWhatsApp
                            ? const Color(0xFF25D366).withValues(alpha: 0.1)
                            : AppTheme.warmMist,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: phone.isWhatsApp
                              ? const Color(0xFF25D366).withValues(alpha: 0.3)
                              : AppTheme.whisperBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/whatsapp-svgrepo-com.svg',
                            width: 12,
                            height: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone.isWhatsApp ? 'WA' : 'Set WA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: phone.isWhatsApp
                                  ? const Color(0xFF25D366)
                                  : AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_phoneNumbers.length > 1) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removePhoneNumber(index),
                      child: const Icon(LucideIcons.trash2, size: 16, color: AppTheme.destructive),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── Location Section ────────────────────────────────────────────────

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(LucideIcons.mapPin, size: 16, color: AppTheme.accent),
            SizedBox(width: 6),
            Text(
              'Store Location (Digital Address)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your Ghana Post GPS Digital Address (e.g., GA-123-4567) to automatically resolve your store coordinates.',
          style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                controller: _digitalAddressController,
                placeholder: const Text('e.g. GA-123-4567'),
                leading: const Icon(LucideIcons.map, size: 16),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                trailing: _digitalAddressController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          setState(() {
                            _digitalAddressController.clear();
                            _locationUrlController.clear();
                            _resolvedDetails = null;
                          });
                        },
                        child: const Icon(LucideIcons.x, size: 16, color: AppTheme.mutedSteel),
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: ShadButton(
                onPressed: _isLookingUpAddress ? null : _lookupAddress,
                child: _isLookingUpAddress
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Resolve'),
              ),
            ),
          ],
        ),
        if (_resolvedDetails != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.successMoss.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.successMoss.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.checkCircle2, color: AppTheme.successMoss, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resolvedDetails!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.charcoalInk),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_locationUrlController.text.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: _previewLocation,
                  leading: const Icon(LucideIcons.eye, size: 16),
                  child: const Text('Preview Store Map Location'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Preview the resolved Google Maps location above before saving.',
            style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
          ),
        ],
      ],
    );
  }

  void _previewLocation() async {
    final url = _locationUrlController.text.trim();
    if (url.isEmpty) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  // ── QR Code Section ────────────────────────────────────────────────

  Widget _buildQrCodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.qrCode, size: 18, color: AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Public Store QR Code',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Allow visitors to view and download your store QR code',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
          Switch(
            value: _qrCodePublic,
            onChanged: (value) => setState(() => _qrCodePublic = value),
            activeThumbColor: AppTheme.accent,
          ),
        ],
      ),
    );
  }
}
