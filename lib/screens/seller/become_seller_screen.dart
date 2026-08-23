import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/seller_onboarding_service.dart';
import '../../utils/responsive.dart';

/// One-way onboarding that turns a buyer account into a seller account.
///
/// Nothing is persisted until the final "Become a Seller" tap, which calls
/// the `become_seller` RPC (business profile upsert + `users.is_seller`
/// flip in one transaction). The flag is permanent by design — the
/// commitment step makes that explicit before anything is submitted.
/// After conversion, an optional identity-verification step is offered
/// with a skip button.
class BecomeSellerScreen extends ConsumerStatefulWidget {
  const BecomeSellerScreen({super.key});

  @override
  ConsumerState<BecomeSellerScreen> createState() =>
      _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends ConsumerState<BecomeSellerScreen> {
  static const _steps = ['Overview', 'Commitment', 'Business Profile', 'Get Verified'];

  int _currentStep = 0;
  bool _acknowledged = false;
  bool _submitting = false;

  /// True once the RPC has committed — step 3 (verification offer) and the
  /// success view are only reachable afterwards.
  bool _completed = false;
  bool _showSuccess = false;

  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ─── Submit ────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _businessNameController.text.trim();
    if (name.length < 2) {
      ShadToaster.of(context).show(
        const ShadToast(
            title: Text('Please enter a business name (at least 2 characters)')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await SellerOnboardingService.becomeSeller(
        businessName: name,
        description: _descriptionController.text.trim(),
      );
      // Refresh the profile so isSeller flips everywhere (nav, menus).
      await ref.read(authProvider).loadUserProfile();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _completed = true;
        _currentStep = 3;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ShadToaster.of(context).show(
        const ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Could not complete onboarding. Please try again.'),
        ),
      );
    }
  }

  Future<void> _startVerification() async {
    // The verification flow manages its own lifecycle; when the user
    // finishes (or backs out of) it, land on the success view.
    await Navigator.of(context).pushNamed('/seller-profile-verification');
    if (!mounted) return;
    setState(() => _showSuccess = true);
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 1:
        return _acknowledged;
      default:
        return true;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (_showSuccess) {
      return _buildSuccess();
    }

    // Deep-linked sellers (or users finishing on another device) shouldn't
    // re-run an irreversible flow. Checked after _showSuccess/_completed so
    // a just-converted user still sees their verification offer.
    if (!_completed && auth.user?.isSeller == true) {
      return _buildAlreadySeller();
    }

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Become a Seller',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.charcoalInk,
              ),
            ),
            Text(
              'Step ${_currentStep + 1} of ${_steps.length}',
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                color: AppTheme.mutedSteel,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.of(context).padding.top + kToolbarHeight + 16,
          16,
          MediaQuery.of(context).padding.bottom + 90,
        ),
        child: _buildCurrentStep(),
      ),
      bottomNavigationBar: _buildNavigationButtons(),
    );
  }

  // ─── Steps ─────────────────────────────────────────────────────

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Overview();
      case 1:
        return _buildStep1Commitment();
      case 2:
        return _buildStep2BusinessProfile();
      case 3:
        return _buildStep3Verification();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep0Overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: context.rw(64),
            height: context.rw(64),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(LucideIcons.store,
                  size: context.ri(28), color: AppTheme.accent),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sell on Instiy',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Turn what you make or do into a store classmates can discover.',
          style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: LucideIcons.sparkles,
          title: 'What you get',
          items: const [
            'List products and services on your own store page',
            'Receive payments into your Instiy wallet',
            'Track orders, reviews and analytics from your dashboard',
          ],
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: LucideIcons.shieldCheck,
          title: 'What we expect',
          items: const [
            'Fulfil the orders you receive and keep listings accurate',
            'Respond to buyer messages promptly',
            'Follow Instiy\'s seller policies — violations affect your account',
          ],
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return AppTheme.frosted(
      radius: 14,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.check,
                        size: 14, color: AppTheme.successMoss),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.mutedSteel,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1Commitment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Before you continue',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Please read this carefully.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.destructive.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.destructive.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 18, color: AppTheme.destructive),
                  SizedBox(width: 8),
                  Text(
                    'This cannot be undone.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.destructive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Once you become a seller, your account stays a seller account. '
                'You can stop listing at any time, but the seller role itself is '
                'permanent for this account.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acknowledged,
              onChanged: (val) => setState(() => _acknowledged = val ?? false),
              activeColor: AppTheme.accent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'I understand that becoming a seller is permanent and cannot '
                  'be reversed on this account.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedSteel,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The verified badge is a separate, optional step you can take '
                  'later from your dashboard.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2BusinessProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your business profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'This is how your store appears to buyers. You can expand it after setup.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),
        const Text(
          'Business Name',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: _businessNameController,
          placeholder: const Text('e.g. Adaeze\'s Thrift Finds'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Description (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: _descriptionController,
          placeholder: const Text('What do you sell or offer?'),
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contact numbers, banner and location can be added from your '
                  'dashboard after you finish — phone numbers are verified by SMS there.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Verification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: context.rw(64),
            height: context.rw(64),
            decoration: BoxDecoration(
              color: AppTheme.successMoss.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(LucideIcons.shieldCheck,
                  size: context.ri(28), color: AppTheme.successMoss),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Welcome aboard!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You\'re now a seller on Instiy. One more thing — would you like to '
          'get verified?',
          style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: LucideIcons.badgeCheck,
          title: 'Why get verified?',
          items: const [
            'A verified badge on your profile and listings',
            'Buyers trust and buy from verified sellers more',
            'Verification is reviewed by our team (student ID + a short video)',
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Completely optional — you can skip this and verify any time '
                  'later from your dashboard.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Terminal Views ────────────────────────────────────────────

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Become a Seller'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppTheme.successMoss,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check,
                    size: 36, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome, ${_businessNameController.text.trim()}!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account is now a seller account. Your dashboard is ready — '
                'add your first listing whenever you like.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
              ),
              const SizedBox(height: 28),
              ShadButton(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/seller-dashboard', (r) => false),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlreadySeller() {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Become a Seller'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.store,
                  size: 40, color: AppTheme.successMoss),
              const SizedBox(height: 16),
              const Text(
                'You\'re already a seller',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This account is permanently a seller account.',
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              const SizedBox(height: 24),
              ShadButton(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/seller-dashboard', (r) => false),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Navigation Buttons ────────────────────────────────────────

  Widget _buildNavigationButtons() {
    // Step 3 (post-conversion verification offer) has its own buttons.
    if (_completed && _currentStep == 3) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          10,
          0,
          10,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: AppTheme.frosted(
          radius: 20,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => setState(() => _showSuccess = true),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Skip for now'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ShadButton(
                    onPressed: _startVerification,
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Start Verification'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        0,
        10,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: AppTheme.frosted(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => setState(() => _currentStep--),
                    child: const Text('Back'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _currentStep == 2
                    ? ShadButton(
                        enabled: !_submitting,
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Become a Seller'),
                              ),
                      )
                    : ShadButton(
                        enabled: _canProceed(),
                        onPressed: _canProceed()
                            ? () => setState(() => _currentStep++)
                            : null,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Continue'),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
