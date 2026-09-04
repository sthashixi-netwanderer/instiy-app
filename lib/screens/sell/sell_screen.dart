import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../utils/responsive.dart';
import '../../providers/providers.dart';
import '../../services/business_profile_service.dart';
import '../../widgets/skeleton.dart';

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndSkip());
  }

  Future<void> _checkAndSkip() async {
    final authProv = ref.read(authProvider);
    final productProv = ref.read(productProvider);
    final user = authProv.user;

    if (user != null) {
      await productProv.loadUserListings(user.id, silent: productProv.userListings.isNotEmpty);
      if (mounted && productProv.userListings.isNotEmpty) {
        // User already has listings — check business profile first
        final profile = await BusinessProfileService.getProfile(user.id);
        if (!mounted) return;
        if (profile != null) {
          Navigator.of(context).pushReplacementNamed('/create-listing'); // ignore: unawaited_futures
          return;
        }
        // No business profile — show dialog
        _showBusinessProfileRequiredDialog();
        if (mounted) setState(() => _checking = false);
        return;
      }
    }

    if (mounted) setState(() => _checking = false);
  }

  Future<void> _navigateToCreateListing() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    final profile = await BusinessProfileService.getProfile(user.id);
    if (!mounted) return;

    if (profile == null) {
      _showBusinessProfileRequiredDialog();
      return;
    }

    Navigator.of(context).pushNamed('/create-listing'); // ignore: unawaited_futures
  }

  void _showBusinessProfileRequiredDialog() {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Business Profile Required'),
      description: const Text(
        'You need to set up your business profile before you can list products. '
        'This helps buyers know who they\'re buying from.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/edit-business-profile');
          },
          child: const Text('Set Up Profile'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: Padding(
          padding: context.rAll(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: context.rw(160), height: context.rh(20)),
              SizedBox(height: context.rh(16)),
              Skeleton(width: double.infinity, height: context.rh(100), borderRadius: BorderRadius.circular(context.rr(16))),
              SizedBox(height: context.rh(16)),
              Skeleton(width: double.infinity, height: context.rh(100), borderRadius: BorderRadius.circular(context.rr(16))),
              SizedBox(height: context.rh(16)),
              Skeleton(width: double.infinity, height: context.rh(100), borderRadius: BorderRadius.circular(context.rr(16))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Start Selling')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(24), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(24), context.rw(24), context.rh(24)),
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
                  padding: context.rAll(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(context.rr(16)),
                  ),
                  child: Icon(
                    LucideIcons.store,
                    size: context.ri(48),
                    color: AppTheme.accent,
                  ),
                ),
                SizedBox(height: context.rh(20)),
                Text(
                  'Sell on Instiy',
                  style: TextStyle(
                    fontSize: context.rsp(24),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'Turn your used items into cash. Reach thousands of students on your campus.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(24)),
          Text(
            'How it works',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(16)),
          const _StepItem(
            number: '1',
            title: 'Take Photos',
            description: 'Snap clear photos of your item from different angles.',
          ),
          const _StepItem(
            number: '2',
            title: 'Add Details',
            description: 'Set a price, choose a category, and describe your item.',
          ),
          const _StepItem(
            number: '3',
            title: 'Publish',
            description: 'Your listing goes live instantly for students to see.',
          ),
          const _StepItem(
            number: '4',
            title: 'Sell & Earn',
            description: 'Chat with buyers, arrange pickup, and get paid.',
          ),
          SizedBox(height: context.rh(32)),
          ShadButton(
            onPressed: _navigateToCreateListing,
            child: Text(
              'Start Selling',
              style: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: context.rh(24)),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _StepItem({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: context.rw(36),
            height: context.rh(36),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: context.rw(14)),
          Expanded(
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
                SizedBox(height: context.rh(2)),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppTheme.mutedSteel,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
