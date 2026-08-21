import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/navigation_service.dart';
import '../../main.dart' show appInitialization;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  bool _navigated = false;
  bool _hasError = false;
  String _errorMessage = '';

  /// Minimum time the splash should be visible (600ms).
  static const _minDisplayTime = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _waitForInitAndNavigate();
  }

  Future<void> _waitForInitAndNavigate() async {
    try {
      await Future.wait([appInitialization, Future.delayed(_minDisplayTime)]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
      debugPrint('App initialization failed: $e');
      return;
    }

    if (!mounted || _navigated) return;
    _navigated = true;
    // Signals main.dart's getInitialLink() callback that this screen will
    // no longer read pendingDeepLink, so a late-resolving cold-start link
    // is handled immediately instead of being stranded.
    NavigationService.splashCompleted = true;

    final pending = NavigationService.pendingDeepLink;
    if (pending != null) {
      NavigationService.pendingDeepLink = null;
      unawaited(NavigationService.handleDeepLink(pending));
    } else {
      // Check if user is suspended after auth init
      final auth = ref.read(authProvider);
      if (auth.isSuspended) {
        unawaited(Navigator.of(context).pushReplacementNamed('/suspended'));
      } else {
        unawaited(Navigator.of(context).pushReplacementNamed('/home'));
      }
    }
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
    _waitForInitAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Image.asset(
                  'assets/logo.png',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (_hasError) ...[
              const SizedBox(height: 24),
              Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF78716C),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
