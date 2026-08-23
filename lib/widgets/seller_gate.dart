import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../providers/providers.dart';

/// Route guard for seller-only screens. Only sellers see [child];
/// unauthenticated users are redirected to login and authenticated
/// non-sellers are funnelled into the Become a Seller wizard, so deep
/// links and stale installs never dead-end.
class SellerGate extends ConsumerWidget {
  final Widget child;

  const SellerGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      });
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: SizedBox.shrink(),
      );
    }

    if (auth.user?.isSeller != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/become-seller');
        }
      });
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: SizedBox.shrink(),
      );
    }

    return child;
  }
}
