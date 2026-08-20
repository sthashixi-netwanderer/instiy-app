import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_button.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  ProviderSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onTextChanged);
    _passwordController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(authProvider).isAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        return;
      }
      if (mounted && ref.read(authProvider).isSuspended) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/suspended', (_) => false);
        return;
      }
      // Listen for auth state changes (e.g. Google OAuth completing)
      _authSub = ref.listenManual(authProvider, (previous, next) {
        if (next.isSuspended && mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/suspended', (_) => false);
        } else if (next.isAuthenticated && mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        }
      });
    });
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _isFormValid =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _authSub?.close();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final auth = ref.read(authProvider);
    final success = await auth.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      final auth = ref.read(authProvider);
      if (auth.isSuspended) {
        unawaited(
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/suspended', (_) => false),
        );
      } else {
        unawaited(
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
        );
      }
    }
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
              icon: Icon(
                LucideIcons.arrowLeft,
                color: AppTheme.charcoalInk,
                size: context.ri(28),
              ),
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/home', (route) => false),
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
                      'Sign In',
                      style: TextStyle(
                        fontSize: context.rsp(24),
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    SizedBox(height: context.rh(8)),
                    Text(
                      'Enter your credentials to continue',
                      style: TextStyle(
                        fontSize: context.rsp(14),
                        color: AppTheme.mutedSteel,
                      ),
                    ),
                    SizedBox(height: context.rh(32)),

                    if (auth.error != null) ...[
                      Container(
                        padding: context.rAll(12),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.circleAlert,
                              color: AppTheme.destructive,
                              size: context.ri(20),
                            ),
                            SizedBox(width: context.rw(8)),
                            Expanded(
                              child: Text(
                                auth.error!,
                                style: TextStyle(
                                  color: AppTheme.destructive,
                                  fontSize: context.rsp(13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: context.rh(16)),
                    ],

                    ShadInputFormField(
                      id: 'email',
                      controller: _emailController,
                      label: const Text('Email'),
                      placeholder: const Text('Enter your email'),
                      leading: Icon(LucideIcons.mail, size: context.ri(18)),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value.isEmpty) return 'Please enter your email';
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: context.rh(16)),

                    ShadInputFormField(
                      id: 'password',
                      controller: _passwordController,
                      label: const Text('Password'),
                      placeholder: const Text('Enter your password'),
                      leading: Icon(LucideIcons.lock, size: context.ri(18)),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      trailing: ShadIconButton.ghost(
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
                          size: context.ri(18),
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (value) {
                        if (value.isEmpty) return 'Please enter your password';
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: context.rh(8)),

                    Align(
                      alignment: Alignment.centerRight,
                      child: ShadButton.link(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/forgot-password'),
                        child: const Text('Forgot Password?'),
                      ),
                    ),

                    SizedBox(height: context.rh(16)),

                    AppButton(
                      onPressed: (_isLoading || !_isFormValid) ? null : _handleLogin,
                      enabled: _isFormValid,
                      loading: _isLoading,
                      child: const Text('Sign In'),
                    ),

                    SizedBox(height: context.rh(20)),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            color: AppTheme.mutedSteel,
                            fontSize: context.rsp(14),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Sign Up',
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
                            'or',
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
                          Text('Continue with Google', style: TextStyle(fontSize: context.rsp(14))),
                        ],
                      ),
                    ),

                    SizedBox(height: context.rh(16)),

                    Center(
                      child: ShadButton.link(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/home', (route) => false),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.home,
                              size: context.ri(16),
                              color: AppTheme.mutedSteel,
                            ),
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
