import 'dart:async';
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
import 'accept_policy_screen.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_button.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _tagController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _universityController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  bool _isTagChecking = false;
  bool _isTagTaken = false;
  List<String> _recommendedTags = [];
  Timer? _tagDebounce;
  Timer? _nameDebounce;

  ProviderSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onTextChanged);
    _nameController.addListener(_onNameChanged);
    _emailController.addListener(_onTextChanged);
    _tagController.addListener(_onTextChanged);
    _tagController.addListener(_onTagChanged);
    _phoneController.addListener(_onTextChanged);
    _universityController.addListener(_onTextChanged);
    _passwordController.addListener(_onTextChanged);
    _confirmPasswordController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(authProvider).isAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        return;
      }
      // Listen for auth state changes (e.g. Google OAuth completing)
      _authSub = ref.listenManual(authProvider, (previous, next) {
        if (next.isAuthenticated && mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        }
      });
    });
  }

  void _onTextChanged() {
    setState(() {});
  }

  void _onNameChanged() {
    if (_nameDebounce?.isActive ?? false) _nameDebounce!.cancel();
    final name = _nameController.text.trim();
    if (name.length < 3) {
      setState(() {
        _recommendedTags = [];
      });
      return;
    }

    _nameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final recs = await AuthService.generateRecommendedTags(name);
      if (mounted) {
        setState(() {
          _recommendedTags = recs;
        });
      }
    });
  }

  void _onTagChanged() {
    if (_tagDebounce?.isActive ?? false) _tagDebounce!.cancel();
    final tag = _tagController.text.trim().replaceAll(RegExp(r'^\$'), '').toLowerCase();

    if (tag.isEmpty || tag.length < 5) {
      setState(() {
        _isTagTaken = false;
      });
      return;
    }

    _tagDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isTagChecking = true);
      try {
        final taken = await AuthService.checkWalletTagExists(tag);
        if (mounted) {
          setState(() {
            _isTagTaken = taken;
            _isTagChecking = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isTagChecking = false);
        }
      }
    });
  }

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _tagController.text.trim().isNotEmpty &&
      !_isTagTaken &&
      _phoneController.text.trim().isNotEmpty &&
      _universityController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _authSub?.close();
    _nameController.dispose();
    _emailController.dispose();
    _tagController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _universityController.dispose();
    _tagDebounce?.cancel();
    _nameDebounce?.cancel();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_universityController.text.trim().isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please select your university')),
      );
      return;
    }

    final tag = _tagController.text.trim().replaceAll(RegExp(r'^\$'), '').toLowerCase();
    final tagExists = await AuthService.checkWalletTagExists(tag);
    if (tagExists) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('This wallet tag is already taken.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AcceptPolicyScreen(),
      ),
    );

    if (accepted != true || !mounted) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    final emailExists = await AuthService.checkEmailExists(email);
    if (emailExists) {
      setState(() => _isLoading = false);
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('An account with this email already exists.')),
        );
      }
      return;
    }

    final phoneExists = await AuthService.isPhoneTaken(phone);
    if (phoneExists) {
      setState(() => _isLoading = false);
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('An account with this phone number already exists.')),
        );
      }
      return;
    }

    final otp = (100000 + Random().nextInt(900000)).toString();

    final otpSent = await SmsService.sendOtp(to: phone, otp: otp);

    setState(() => _isLoading = false);

    if (!otpSent) {
      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(title: Text('Failed to send verification code. Please check your phone number.')),
        );
      }
      return;
    }

    if (mounted) {
      _showOtpVerificationDialog(otp, phone);
    }
  }

  void _showOtpVerificationDialog(String correctOtp, String phoneNumber) {
    final otpController = TextEditingController();
    final phoneEditController = TextEditingController(text: phoneNumber);
    bool isVerifying = false;
    bool isResending = false;
    bool isEditingPhone = false;
    String? otpError;
    String currentOtp = correctOtp;
    String currentPhone = phoneNumber;

    int resendCountdown = 30;
    Timer? countdownTimer;
    bool hasStartedTimer = false;

    void startTimer(StateSetter setDialogState) {
      resendCountdown = 30;
      countdownTimer?.cancel();
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setDialogState(() {
          if (resendCountdown > 0) {
            resendCountdown--;
          } else {
            timer.cancel();
          }
        });
      });
    }

    AppTheme.showGlassDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasStartedTimer) {
              hasStartedTimer = true;
              startTimer(setDialogState);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditingPhone ? 'Edit Phone Number' : 'Verify Phone Number',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                if (isEditingPhone) ...[
                  Text(
                    'Enter your correct phone number to receive the verification code.',
                    style: TextStyle(
                      fontSize: context.rsp(14),
                      color: AppTheme.mutedSteel,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: context.rh(12)),
                  ShadInput(
                    controller: phoneEditController,
                    placeholder: const Text('Enter new phone number'),
                    keyboardType: TextInputType.phone,
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'We sent a 6-digit verification code to $currentPhone. Please enter it below to verify your account.',
                          style: TextStyle(
                            fontSize: context.rsp(14),
                            color: AppTheme.mutedSteel,
                            height: 1.4,
                          ),
                        ),
                      ),
                      ShadIconButton.ghost(
                        icon: Icon(LucideIcons.pencil, size: context.ri(16), color: AppTheme.accent),
                        onPressed: () {
                          setDialogState(() {
                            isEditingPhone = true;
                            otpError = null;
                            phoneEditController.text = currentPhone;
                          });
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: context.rh(16)),
                  ShadInput(
                    controller: otpController,
                    placeholder: const Text('Enter 6-digit code'),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (val) {
                      setDialogState(() {});
                    },
                  ),
                ],
                if (otpError != null) ...[
                  SizedBox(height: context.rh(8)),
                  Text(
                    otpError!,
                    style: TextStyle(color: AppTheme.destructive, fontSize: context.rsp(13)),
                  ),
                ],
                if (isVerifying) ...[
                  SizedBox(height: context.rh(16)),
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                SizedBox(height: context.rh(20)),
                if (isEditingPhone) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ShadButton.outline(
                        onPressed: isVerifying
                            ? null
                            : () {
                                setDialogState(() {
                                  isEditingPhone = false;
                                  phoneEditController.text = currentPhone;
                                  otpError = null;
                                });
                              },
                        child: const Text('Cancel'),
                      ),
                      SizedBox(width: context.rw(8)),
                      ShadButton(
                        onPressed: isVerifying
                            ? null
                            : () async {
                                final newPhone = phoneEditController.text.trim();
                                final cleaned = newPhone.replaceAll(RegExp(r'\D'), '');
                                if (cleaned.length < 9) {
                                  setDialogState(() {
                                    otpError = 'Please enter a valid phone number';
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isVerifying = true;
                                  otpError = null;
                                });

                                try {
                                  final taken = await AuthService.isPhoneTaken(newPhone);
                                  if (taken) {
                                    setDialogState(() {
                                      isVerifying = false;
                                      otpError = 'Phone number already registered';
                                    });
                                    return;
                                  }

                                  final newOtp = (100000 + Random().nextInt(900000)).toString();
                                  final sent = await SmsService.sendOtp(to: newPhone, otp: newOtp);
                                  
                                  if (!sent) {
                                    setDialogState(() {
                                      isVerifying = false;
                                      otpError = 'Failed to send OTP. Try again.';
                                    });
                                    return;
                                  }

                                  setDialogState(() {
                                    currentPhone = newPhone;
                                    currentOtp = newOtp;
                                    isEditingPhone = false;
                                    isVerifying = false;
                                    _phoneController.text = newPhone;
                                  });

                                  startTimer(setDialogState);
                                } catch (e) {
                                  setDialogState(() {
                                    isVerifying = false;
                                    otpError = 'Error: ${e.toString()}';
                                  });
                                }
                              },
                        child: const Text('Save & Send Code'),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: (isVerifying || resendCountdown > 0)
                                ? null
                                : () async {
                                    setDialogState(() {
                                      isResending = true;
                                      otpError = null;
                                    });

                                    try {
                                      final newOtp = (100000 + Random().nextInt(900000)).toString();
                                      final sent = await SmsService.sendOtp(to: currentPhone, otp: newOtp);

                                      if (sent) {
                                        setDialogState(() {
                                          currentOtp = newOtp;
                                          isResending = false;
                                        });
                                        startTimer(setDialogState);
                                      } else {
                                        setDialogState(() {
                                          isResending = false;
                                          otpError = 'Failed to resend code. Try again.';
                                        });
                                      }
                                    } catch (e) {
                                      setDialogState(() {
                                        isResending = false;
                                        otpError = e.toString();
                                      });
                                    }
                                  },
                            child: Text(
                              resendCountdown > 0 ? 'Resend code in ${resendCountdown}s' : 'Resend Code',
                              style: TextStyle(
                                fontSize: context.rsp(13),
                                color: resendCountdown > 0 ? AppTheme.mutedSteel : AppTheme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isResending) ...[
                            SizedBox(width: context.rw(4)),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          ShadButton.outline(
                            onPressed: isVerifying ? null : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          SizedBox(width: context.rw(8)),
                          ShadButton(
                            onPressed: (isVerifying || otpController.text.trim().length != 6)
                                ? null
                                : () async {
                                    final inputOtp = otpController.text.trim();
                                    if (inputOtp.length != 6) {
                                      setDialogState(() {
                                        otpError = 'Enter a valid 6-digit code';
                                      });
                                      return;
                                    }

                                    if (inputOtp != currentOtp) {
                                      setDialogState(() {
                                        otpError = 'Incorrect code. Please try again.';
                                      });
                                      return;
                                    }

                                    setDialogState(() {
                                      isVerifying = true;
                                      otpError = null;
                                    });

                                    final navigator = Navigator.of(context);
                                    final auth = ref.read(authProvider);

                                    final success = await auth.signUp(
                                      email: _emailController.text.trim(),
                                      password: _passwordController.text,
                                      fullName: _nameController.text.trim(),
                                      walletTag: _tagController.text.trim().replaceAll(RegExp(r'^\$'), '').toLowerCase(),
                                      university: _universityController.text.trim(),
                                      phoneNumber: currentPhone,
                                    );

                                    setDialogState(() {
                                      isVerifying = false;
                                    });

                                    if (success) {
                                      navigator.pop();
                                      if (mounted) {
                                        navigator.pushNamedAndRemoveUntil('/home', (_) => false); // ignore: unawaited_futures
                                      }
                                    } else {
                                      setDialogState(() {
                                        otpError = auth.error ?? 'Registration failed. Please try again.';
                                      });
                                    }
                                  },
                            child: const Text('Verify & Sign Up'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
      },
    ).then((_) {
      otpController.dispose();
      phoneEditController.dispose();
      countdownTimer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.cleanBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ShadIconButton.ghost(
              icon: Icon(LucideIcons.arrowLeft, color: AppTheme.charcoalInk, size: context.ri(28)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: context.rAll(30),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: context.rsp(24),
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(height: context.rh(8)),
                    Text(
                      'Join the student marketplace',
                      style: TextStyle(
                        fontSize: context.rsp(14),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                    SizedBox(height: context.rh(24)),

                    if (auth.error != null) ...[
                      Container(
                        padding: context.rAll(12),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.circleAlert, color: AppTheme.destructive, size: context.ri(20)),
                            SizedBox(width: context.rw(8)),
                            Expanded(
                              child: Text(
                                auth.error!,
                                style: TextStyle(color: AppTheme.destructive, fontSize: context.rsp(13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: context.rh(16)),
                    ],

                    ShadInputFormField(
                      id: 'name',
                      controller: _nameController,
                      label: const Text('Full Name'),
                      placeholder: const Text('Enter your full name'),
                      leading: Icon(LucideIcons.user, size: context.ri(18)),
                      textInputAction: TextInputAction.next,
                      validator: (v) => v.isEmpty ? 'Please enter your name' : null,
                    ),
                    SizedBox(height: context.rh(12)),

                    ShadInputFormField(
                      id: 'email',
                      controller: _emailController,
                      label: const Text('Email'),
                      placeholder: const Text('Enter your university email'),
                      leading: Icon(LucideIcons.mail, size: context.ri(18)),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v.isEmpty) return 'Please enter your email';
                        if (!v.contains('@')) return 'Please enter a valid email';
                        return null;
                      },
                    ),
                    SizedBox(height: context.rh(12)),

                    ShadInputFormField(
                      id: 'wallet_tag',
                      controller: _tagController,
                      label: const Text('Wallet Tag'),
                      placeholder: const Text('Enter your unique wallet tag'),
                      leading: Icon(LucideIcons.wallet, size: context.ri(18)),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v.isEmpty) return 'Please enter a wallet tag';
                        final cleaned = v.replaceAll(RegExp(r'^\$'), '');
                        
                        // Count alphabetic characters in the tag
                        final alphabeticCount = cleaned.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
                        if (alphabeticCount < 5) {
                          return 'Tag must contain at least 5 alphabetic characters';
                        }
                        if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(cleaned)) {
                          return 'Only alphanumeric characters are allowed';
                        }
                        if (_isTagTaken) {
                          return 'This wallet tag is already taken';
                        }
                        return null;
                      },
                      trailing: _isTagChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _tagController.text.trim().isNotEmpty
                              ? Icon(
                                  _isTagTaken ? LucideIcons.circleX : LucideIcons.circleCheck,
                                  color: _isTagTaken ? AppTheme.destructive : Colors.green,
                                  size: 18,
                                )
                              : null,
                    ),
                    if (_recommendedTags.isNotEmpty) ...[
                      SizedBox(height: context.rh(8)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recommended Tags:',
                          style: TextStyle(
                            fontSize: context.rsp(12),
                            color: AppTheme.mutedSteel,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(height: context.rh(6)),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _recommendedTags.map((tag) {
                          return GestureDetector(
                            onTap: () {
                              _tagController.text = tag;
                              _onTagChanged();
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '\$$tag',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: context.rsp(12),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    SizedBox(height: context.rh(12)),

                    ShadInputFormField(
                      id: 'phone',
                      controller: _phoneController,
                      label: const Text('Phone Number'),
                      placeholder: const Text('e.g., 0200585542'),
                      leading: Icon(LucideIcons.phone, size: context.ri(18)),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v.isEmpty) return 'Please enter your phone number';
                        final cleaned = v.replaceAll(RegExp(r'\D'), '');
                        if (cleaned.length < 9) return 'Please enter a valid phone number';
                        return null;
                      },
                    ),
                    SizedBox(height: context.rh(12)),

                    SearchableInstitutionPicker(
                      selectedValue: _universityController.text.isEmpty ? null : _universityController.text,
                      onSelected: (val) {
                        setState(() {
                          _universityController.text = val ?? '';
                        });
                      },
                      label: 'University *',
                      hint: 'Select your university...',
                    ),
                    SizedBox(height: context.rh(12)),

                    ShadInputFormField(
                      id: 'password',
                      controller: _passwordController,
                      label: const Text('Password'),
                      placeholder: const Text('Create a password'),
                      leading: Icon(LucideIcons.lock, size: context.ri(18)),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      trailing: ShadIconButton.ghost(
                        icon: Icon(
                          _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: context.ri(18),
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if (v.isEmpty) return 'Please enter a password';
                        if (v.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    SizedBox(height: context.rh(12)),

                    ShadInputFormField(
                      id: 'confirmPassword',
                      controller: _confirmPasswordController,
                      label: const Text('Confirm Password'),
                      placeholder: const Text('Confirm your password'),
                      leading: Icon(LucideIcons.lock, size: context.ri(18)),
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      trailing: ShadIconButton.ghost(
                        icon: Icon(
                          _obscureConfirmPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: context.ri(18),
                        ),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                      validator: (v) {
                        if (v.isEmpty) return 'Please confirm your password';
                        if (v != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    SizedBox(height: context.rh(24)),

                    AppButton(
                      onPressed: (_isLoading || !_isFormValid) ? null : _handleRegister,
                      enabled: _isFormValid,
                      loading: _isLoading,
                      child: const Text('Create Account'),
                    ),

                    SizedBox(height: context.rh(16)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Already have an account? ",
                          style: TextStyle(
                            color: AppTheme.mutedSteel,
                            fontSize: context.rsp(14),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Text(
                            'Sign In',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: context.rsp(14),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: context.rh(20)),

                    Row(
                      children: [
                        Expanded(child: Divider(color: AppTheme.whisperBorder)),
                        Padding(
                          padding: context.rPadding(horizontal: 16),
                          child: Text(
                            'Or continue with',
                            style: TextStyle(
                              color: AppTheme.mutedSteel,
                              fontSize: context.rsp(14),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppTheme.whisperBorder)),
                      ],
                    ),

                    SizedBox(height: context.rh(20)),

                    AppButton.outline(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final accepted = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => const AcceptPolicyScreen(),
                                ),
                              );
                              if (accepted != true || !mounted) return;

                              setState(() => _isLoading = true);
                              await auth.signInWithGoogle();
                              if (mounted) setState(() => _isLoading = false);
                            },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.network(
                            'https://developers.google.com/static/identity/images/g-logo.png',
                            height: context.rh(22),
                            width: context.rw(22),
                            errorBuilder: (context, error, stackTrace) => Icon(LucideIcons.globe, size: context.ri(24)),
                          ),
                          SizedBox(width: context.rw(12)),
                          Text('Google', style: TextStyle(fontSize: context.rsp(14))),
                        ],
                      ),
                    ),

                    SizedBox(height: context.rh(16)),

                    Center(
                      child: ShadButton.link(
                        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.home, size: context.ri(16), color: AppTheme.mutedSteel),
                            SizedBox(width: context.rw(6)),
                            Text(
                              'Back to Home',
                              style: TextStyle(
                                color: AppTheme.mutedSteel,
                                fontSize: context.rsp(14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: context.rh(20)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
