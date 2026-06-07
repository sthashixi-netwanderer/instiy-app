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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _universityController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onTextChanged);
    _emailController.addListener(_onTextChanged);
    _phoneController.addListener(_onTextChanged);
    _universityController.addListener(_onTextChanged);
    _passwordController.addListener(_onTextChanged);
    _confirmPasswordController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _universityController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _universityController.dispose();
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
    bool isVerifying = false;
    String? otpError;

    AppTheme.showGlassDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify Phone Number',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'We sent a 6-digit verification code to $phoneNumber. Please enter it below to verify your account.',
                  style: TextStyle(
                    fontSize: context.rsp(14),
                    color: AppTheme.mutedSteel,
                    height: 1.4,
                  ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
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

                              if (inputOtp != correctOtp) {
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
                                university: _universityController.text.trim(),
                                phoneNumber: phoneNumber,
                              );

                              setDialogState(() {
                                isVerifying = false;
                              });

                              if (success) {
                                navigator.pop();
                                if (mounted) {
                                  navigator.pushNamedAndRemoveUntil('/home', (_) => false);
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
            );
          },
        );
      },
    ).then((_) {
      otpController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        }
      });
    }

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.canvasWhite,
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

                    SizedBox(
                      height: context.rh(50),
                      child: ShadButton(
                        onPressed: (_isLoading || !_isFormValid) ? null : _handleRegister,
                        child: _isLoading
                            ? SizedBox(
                                height: context.rh(20),
                                width: context.rw(20),
                                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Create Account'),
                      ),
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

                    ShadButton.outline(
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
                              await auth.signInWithGoogle(isSignUp: true);
                              if (mounted) setState(() => _isLoading = false);
                            },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.network(
                            'https://developers.google.com/static/identity/images/g-logo.png',
                            height: context.rh(22),
                            width: context.rw(22),
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(LucideIcons.globe, size: context.ri(24));
                            },
                          ),
                          SizedBox(width: context.rw(12)),
                          Text(
                            'Google',
                            style: TextStyle(fontSize: context.rsp(14)),
                          ),
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
