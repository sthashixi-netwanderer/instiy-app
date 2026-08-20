import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';
import '../../services/sms_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/searchable_institution_picker.dart';

class GoogleOnboardingView extends ConsumerStatefulWidget {
  const GoogleOnboardingView({super.key});

  @override
  ConsumerState<GoogleOnboardingView> createState() => _GoogleOnboardingViewState();
}

class _GoogleOnboardingViewState extends ConsumerState<GoogleOnboardingView> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String? _selectedUniversity;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _correctOtp;
  String? _errorMsg;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtpCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = 'Please enter your phone number');
      return;
    }

    if (_selectedUniversity == null || _selectedUniversity!.isEmpty) {
      setState(() => _errorMsg = 'Please select your university');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final phoneTaken = await AuthService.isPhoneTaken(phone);
      if (phoneTaken) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'An account with this phone number already exists.';
        });
        return;
      }

      final otp = (100000 + Random().nextInt(900000)).toString();
      final sent = await SmsService.sendOtp(to: phone, otp: otp);

      setState(() {
        _isLoading = false;
        if (sent) {
          _otpSent = true;
          _correctOtp = otp;
          _errorMsg = null;
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Verification code sent!')),
          );
        } else {
          _errorMsg = 'Failed to send verification code. Please check the number.';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'An error occurred: $e';
      });
    }
  }

  Future<void> _verifyAndComplete() async {
    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.length != 6) {
      setState(() => _errorMsg = 'Enter a valid 6-digit code');
      return;
    }

    if (enteredOtp != _correctOtp) {
      setState(() => _errorMsg = 'Incorrect code. Please try again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final auth = ref.read(authProvider);

      // Update DB profile
      await AuthService.updateProfile(
        university: _selectedUniversity,
        phoneNumber: _phoneController.text.trim(),
      );

      // Refresh auth provider state to let the user enter
      await auth.loadUserProfile();

      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Profile completed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Failed to complete profile: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: context.rAll(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.rw(400)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top logo / icon
                Center(
                  child: Container(
                    padding: context.rAll(16),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.userCheck,
                      color: AppTheme.accent,
                      size: context.ri(40),
                    ),
                  ),
                ),
                SizedBox(height: context.rh(24)),
                Text(
                  'Complete Your Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(24),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'Select your university campus and verify your phone number to continue to Instiy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    color: AppTheme.mutedSteel,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: context.rh(32)),

                // Error message
                if (_errorMsg != null) ...[
                  Container(
                    padding: context.rAll(12),
                    decoration: BoxDecoration(
                      color: AppTheme.destructive.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(context.rr(8)),
                      border: Border.all(color: AppTheme.destructive.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.alertTriangle, size: context.ri(16), color: AppTheme.destructive),
                        SizedBox(width: context.rw(8)),
                        Expanded(
                          child: Text(
                            _errorMsg!,
                            style: TextStyle(fontSize: context.rsp(13), color: AppTheme.destructive),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.rh(16)),
                ],

                // University Picker (Disabled when OTP is sent)
                SearchableInstitutionPicker(
                  selectedValue: _selectedUniversity,
                  onSelected: _otpSent
                      ? (_) {}
                      : (val) {
                          setState(() {
                            _selectedUniversity = val;
                          });
                        },
                  label: 'University *',
                  hint: 'Select your university...',
                ),
                SizedBox(height: context.rh(16)),

                // Phone Input (Disabled when OTP is sent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Phone Number *',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: context.rsp(14),
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(height: context.rh(8)),
                    ShadInput(
                      controller: _phoneController,
                      placeholder: const Text('E.g., 0200585542'),
                      keyboardType: TextInputType.phone,
                      enabled: !_otpSent,
                      leading: Icon(LucideIcons.phone, size: context.ri(18)),
                    ),
                  ],
                ),
                SizedBox(height: context.rh(16)),

                // OTP Verification Section
                if (_otpSent) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Verification Code *',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: context.rsp(14),
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                      SizedBox(height: context.rh(8)),
                      ShadInput(
                        controller: _otpController,
                        placeholder: const Text('Enter 6-digit code'),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                      SizedBox(height: context.rh(24)),
                      ShadButton(
                        onPressed: _isLoading ? null : _verifyAndComplete,
                        child: _isLoading
                            ? SizedBox(
                                width: context.rw(20),
                                height: context.rh(20),
                                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Verify & Continue'),
                      ),
                    ],
                  ),
                ] else ...[
                  ShadButton(
                    onPressed: _isLoading ? null : _sendOtpCode,
                    child: _isLoading
                        ? SizedBox(
                            width: context.rw(20),
                            height: context.rh(20),
                            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Send Verification Code'),
                  ),
                ],

                SizedBox(height: context.rh(32)),

                // Back / Log out option
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await auth.signOut();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.logOut, size: context.ri(16), color: AppTheme.mutedSteel),
                        SizedBox(width: context.rw(6)),
                        Text(
                          'Sign Out',
                          style: TextStyle(
                            color: AppTheme.mutedSteel,
                            fontSize: context.rsp(14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
