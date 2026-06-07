import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _isFormValid => _emailController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await AuthService.resetPassword(_emailController.text.trim());
      if (mounted) setState(() => _emailSent = true);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('Error'),
            description: Text(e.toString().replaceAll('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      appBar: AppTheme.glassAppBar(context: context,
        title: const Text('Reset Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: context.rAll(24),
          child: _emailSent ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: context.rh(20)),
          Icon(
            LucideIcons.lockKeyhole,
            size: context.ri(48),
            color: AppTheme.accent,
          ),
          SizedBox(height: context.rh(20)),
          Text(
            'Forgot Password?',
            style: TextStyle(
              fontSize: context.rsp(24),
              fontWeight: FontWeight.bold,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Enter your email address and we\'ll send you a link to reset your password.',
            style: TextStyle(
              fontSize: context.rsp(14),
              color: AppTheme.mutedSteel,
              height: 1.5,
            ),
          ),
          SizedBox(height: context.rh(32)),
          Text(
            'Email',
            style: TextStyle(
              fontSize: context.rsp(14),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          ShadInputFormField(
            id: 'email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            placeholder: const Text('Enter your email'),
            leading: Padding(
              padding: EdgeInsets.only(left: context.rw(12), right: context.rw(8)),
              child: Icon(LucideIcons.mail, size: context.ri(18)),
            ),
            validator: (v) {
              if (v.isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          SizedBox(height: context.rh(24)),
          SizedBox(
            height: context.rh(50),
            width: double.infinity,
            child: ShadButton(
              onPressed: (_isLoading || !_isFormValid) ? null : _handleSendResetLink,
              child: _isLoading
                  ? SizedBox(
                      height: context.rh(20),
                      width: context.rw(20),
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send Reset Link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: context.rAll(20),
          decoration: BoxDecoration(
            color: AppTheme.successMoss.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.mailCheck,
            size: context.ri(48),
            color: AppTheme.successMoss,
          ),
        ),
        SizedBox(height: context.rh(24)),
        Text(
          'Check Your Email',
          style: TextStyle(
            fontSize: context.rsp(24),
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(12)),
        Text(
          'We\'ve sent a password reset link to\n${_emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rsp(14),
            color: AppTheme.mutedSteel,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.rh(32)),
        SizedBox(
          height: context.rh(50),
          width: double.infinity,
          child: ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Login'),
          ),
        ),
        SizedBox(height: context.rh(16)),
        ShadButton.link(
          onPressed: () {
            setState(() => _emailSent = false);
            _handleSendResetLink();
          },
          child: const Text('Didn\'t receive the email? Resend'),
        ),
      ],
    );
  }
}
