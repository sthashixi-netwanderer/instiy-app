import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_button.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _passwordUpdated = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onTextChanged);
    _confirmPasswordController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _isFormValid => _passwordController.text.isNotEmpty && _confirmPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await SupabaseService.auth.updateUser(
        UserAttributes(password: _passwordController.text.trim()),
      );
      if (mounted) setState(() => _passwordUpdated = true);
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
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context,
        title: const Text('Set New Password'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(context.rw(24), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(24), context.rw(24), context.rh(24)),
        child: _passwordUpdated ? _buildSuccessView() : _buildFormView(),
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
            'Create New Password',
            style: TextStyle(
              fontSize: context.rsp(24),
              fontWeight: FontWeight.bold,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            'Your new password must be at least 6 characters long.',
            style: TextStyle(
              fontSize: context.rsp(14),
              color: AppTheme.mutedSteel,
              height: 1.5,
            ),
          ),
          SizedBox(height: context.rh(32)),
          Text(
            'New Password',
            style: TextStyle(
              fontSize: context.rsp(14),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          ShadInputFormField(
            id: 'password',
            controller: _passwordController,
            obscureText: _obscurePassword,
            placeholder: const Text('Enter new password'),
            leading: Padding(
              padding: EdgeInsets.only(left: context.rw(12), right: context.rw(8)),
              child: Icon(LucideIcons.lock, size: context.ri(18)),
            ),
            trailing: GestureDetector(
              onTap: () => setState(() => _obscurePassword = !_obscurePassword),
              child: Padding(
                padding: EdgeInsets.only(right: context.rw(12)),
                child: Icon(
                  _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: context.ri(18),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ),
            validator: (v) {
              if (v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Password must be at least 6 characters';
              return null;
            },
          ),
          SizedBox(height: context.rh(20)),
          Text(
            'Confirm Password',
            style: TextStyle(
              fontSize: context.rsp(14),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          ShadInputFormField(
            id: 'confirmPassword',
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            placeholder: const Text('Confirm new password'),
            leading: Padding(
              padding: EdgeInsets.only(left: context.rw(12), right: context.rw(8)),
              child: Icon(LucideIcons.lock, size: context.ri(18)),
            ),
            trailing: GestureDetector(
              onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
              child: Padding(
                padding: EdgeInsets.only(right: context.rw(12)),
                child: Icon(
                  _obscureConfirm ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: context.ri(18),
                  color: AppTheme.mutedSteel,
                ),
              ),
            ),
            validator: (v) {
              if (v.isEmpty) return 'Please confirm your password';
              if (v != _passwordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          SizedBox(height: context.rh(32)),
          AppButton(
            onPressed: (_isLoading || !_isFormValid) ? null : _handleResetPassword,
            enabled: _isFormValid,
            loading: _isLoading,
            child: const Text('Reset Password'),
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
            LucideIcons.checkCircle,
            size: context.ri(48),
            color: AppTheme.successMoss,
          ),
        ),
        SizedBox(height: context.rh(24)),
        Text(
          'Password Updated!',
          style: TextStyle(
            fontSize: context.rsp(24),
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        SizedBox(height: context.rh(12)),
        Text(
          'Your password has been successfully reset.\nYou can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rsp(14),
            color: AppTheme.mutedSteel,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.rh(32)),
        AppButton(
          onPressed: () {
            // Sign out and go to login
            SupabaseService.auth.signOut();
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          },
          child: const Text('Go to Login'),
        ),
      ],
    );
  }
}
