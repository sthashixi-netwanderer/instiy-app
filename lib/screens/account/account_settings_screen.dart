import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../providers/sound_provider.dart';
import '../../services/wallet_lock_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_button.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const AccountSettingsScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _walletLockEnabled = false;
  bool _deviceSupported = false;
  final Map<String, bool> _screenLocks = {};

  static const _screenConfig = [
    ('wallet', LucideIcons.wallet, 'Wallet', 'Balance, transfers & withdrawals'),
    ('orders', LucideIcons.shoppingBag, 'Orders', 'Order history & tracking'),
    ('checkout', LucideIcons.creditCard, 'Checkout', 'Payment confirmation'),
    ('seller_orders', LucideIcons.store, 'Seller Orders', 'Incoming orders & earnings'),
    ('seller_dashboard', LucideIcons.layoutDashboard, 'Seller Dashboard', 'Sales stats, listings & drafts'),
    ('messages', LucideIcons.messageSquare, 'Messages', 'Chat conversations'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _loadSettings();
  }

  void _loadSettings() {
    _loadWalletLockState();
    ref.read(soundProvider).initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletLockState() async {
    final enabled = await WalletLockService.isLockEnabled();
    final supported = await WalletLockService.isDeviceSupported();
    final Map<String, bool> locks = {};
    for (final (key, _, _, _) in _screenConfig) {
      locks[key] = await WalletLockService.isScreenLockEnabled(key);
    }
    if (mounted) {
      setState(() {
        _walletLockEnabled = enabled;
        _deviceSupported = supported;
        _screenLocks.addAll(locks);
      });
    }
  }

  Future<void> _toggleWalletLock(bool value) async {
    final reason = value
        ? 'Authenticate to enable app lock'
        : 'Authenticate to confirm disabling app lock';
    final authenticated = await WalletLockService.authenticate(reason: reason);
    if (!authenticated) return;
    await WalletLockService.setLockEnabled(value);
    if (mounted) {
      setState(() {
        _walletLockEnabled = value;
        for (final key in _screenLocks.keys) {
          _screenLocks[key] = value;
        }
      });
      ShadToaster.of(context).show(
        ShadToast(title: Text(value ? 'App lock enabled' : 'App lock disabled')),
      );
    }
  }

  Future<void> _toggleScreenLock(String screenKey, bool value) async {
    if (!value) {
      // Turning OFF a lock requires biometric verification
      final authed = await WalletLockService.authenticate(
        reason: 'Authenticate to disable screen lock',
      );
      if (!authed) return;
    }
    await WalletLockService.setScreenLock(screenKey, value);
    if (mounted) {
      setState(() => _screenLocks[screenKey] = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final ap = ref.watch(authProvider);
    final sp = ref.watch(soundProvider);
    final user = ap.user;

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Settings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.pureSurface.withValues(alpha: 0.7),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.whisperBorder, width: 0.5),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.accent,
                  labelColor: AppTheme.accent,
                  unselectedLabelColor: AppTheme.mutedSteel,
                  labelStyle: TextStyle(
                    fontSize: context.rsp(12),
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: context.rsp(12),
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(icon: Icon(LucideIcons.user), text: 'Profile'),
                    Tab(icon: Icon(LucideIcons.bell), text: 'Notifications'),
                    Tab(icon: Icon(LucideIcons.lock), text: 'App Lock'),
                    Tab(icon: Icon(LucideIcons.settings), text: 'General'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProfileTab(theme, user),
          _buildNotificationsTab(theme, sp),
          _buildAppLockTab(theme),
          _buildGeneralTab(theme),
        ],
      ),
    );
  }

  Widget _buildProfileTab(ShadThemeData theme, dynamic user) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + kTextTabBarHeight;
    return ListView(
      padding: EdgeInsets.fromLTRB(context.rw(16), topPad + context.rh(28), context.rw(16), context.rh(16)),
      children: [
        // Profile summary card
        Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(16)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            children: [
              ShadAvatar(
                user?.avatarUrl?.isNotEmpty == true ? user!.avatarUrl : null,
                size: Size.square(context.rw(80)),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  (user?.fullName ?? 'U')[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.rsp(32),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: context.rh(12)),
              Text(
                user?.fullName ?? 'User',
                style: TextStyle(
                  fontSize: context.rsp(18),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
              if (user?.email?.isNotEmpty == true) ...[
                SizedBox(height: context.rh(4)),
                Text(
                  user!.email!,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
              if (user?.phoneNumber?.isNotEmpty == true) ...[
                SizedBox(height: context.rh(4)),
                Text(
                  user!.phoneNumber!,
                  style: TextStyle(
                    fontSize: context.rsp(13),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
              SizedBox(height: context.rh(16)),
              AppButton(
                onPressed: () => Navigator.of(context).pushNamed('/edit-profile'),
                leading: const Icon(LucideIcons.pencil, size: 18),
                child: const Text('Edit Profile'),
              ),
            ],
          ),
        ),
        SizedBox(height: context.rh(32)),
      ],
    );
  }

  Widget _buildNotificationsTab(ShadThemeData theme, SoundProvider soundProvider) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + kTextTabBarHeight;
    return ListView(
      padding: EdgeInsets.fromLTRB(context.rw(16), topPad + context.rh(28), context.rw(16), context.rh(16)),
      children: [
        Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(16)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.volume2, color: AppTheme.mutedSteel),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('In-App Sounds', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                        SizedBox(height: context.rh(2)),
                        Text('Play sounds for notifications within the app', style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                      ],
                    ),
                  ),
                  Switch(
                    value: soundProvider.isSoundEnabled,
                    onChanged: soundProvider.setSoundEnabled,
                    activeThumbColor: AppTheme.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: context.rh(24)),
        Text('Notification Sound', style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: context.rh(4)),
        Text(
          'Choose the sound that plays when you receive a notification',
          style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
        ),
        SizedBox(height: context.rh(16)),
        ...SoundProvider.availableSounds.map((sound) {
          final isSelected = soundProvider.selectedSoundId == sound.id;
          return Container(
            margin: EdgeInsets.only(bottom: context.rh(8)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.rr(12)),
              border: Border.all(
                color: isSelected ? AppTheme.accent : AppTheme.whisperBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Material(
              color: isSelected ? AppTheme.accent.withValues(alpha: 0.08) : AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(12)),
              child: ListTile(
                leading: Icon(sound.icon, color: isSelected ? AppTheme.accent : AppTheme.mutedSteel),
                title: Text(sound.label, style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.accent : AppTheme.charcoalInk,
                )),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(LucideIcons.play, size: context.ri(20), color: AppTheme.mutedSteel),
                      onPressed: () => soundProvider.previewSound(sound.id),
                    ),
                    if (isSelected)
                      Container(
                        padding: context.rAll(4),
                        decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                        child: Icon(LucideIcons.check, size: context.ri(14), color: Colors.white),
                      ),
                  ],
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.rr(12))),
                onTap: () => soundProvider.setSelectedSound(sound.id),
              ),
            ),
          );
        }),
        SizedBox(height: context.rh(32)),
      ],
    );
  }

  Widget _buildAppLockTab(ShadThemeData theme) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + kTextTabBarHeight;
    return ListView(
      padding: EdgeInsets.fromLTRB(context.rw(16), topPad + context.rh(28), context.rw(16), context.rh(16)),
      children: [
        Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(16)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: context.rAll(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(context.rr(10)),
                    ),
                    child: Icon(LucideIcons.lock, size: context.ri(20), color: AppTheme.accent),
                  ),
                  SizedBox(width: context.rw(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App Lock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.rsp(15), color: AppTheme.charcoalInk)),
                        SizedBox(height: context.rh(2)),
                        Text('Require biometrics or screen lock', style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                      ],
                    ),
                  ),
                  if (_deviceSupported)
                    Switch(
                      value: _walletLockEnabled,
                      onChanged: _toggleWalletLock,
                      activeThumbColor: AppTheme.accent,
                    )
                  else
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(4)),
                      decoration: BoxDecoration(
                        color: AppTheme.warmMist,
                        borderRadius: BorderRadius.circular(context.rr(8)),
                      ),
                      child: Text('Not supported', style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel)),
                    ),
                ],
              ),
              if (_deviceSupported) ...[
                SizedBox(height: context.rh(16)),
                Padding(
                  padding: EdgeInsets.only(left: context.rw(4)),
                  child: Text('Protected screens', style: TextStyle(fontSize: context.rsp(12), fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
                ),
                SizedBox(height: context.rh(8)),
                for (final (key, icon, label, detail) in _screenConfig)
                  _LockScreenItem(
                    icon: icon,
                    label: label,
                    detail: detail,
                    enabled: _screenLocks[key] ?? false,
                    onChanged: (val) => _toggleScreenLock(key, val),
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: context.rh(32)),
      ],
    );
  }

  Widget _buildGeneralTab(ShadThemeData theme) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + kTextTabBarHeight;
    return ListView(
      padding: EdgeInsets.fromLTRB(context.rw(16), topPad + context.rh(28), context.rw(16), context.rh(16)),
      children: [
        _GeneralLinkRow(
          icon: LucideIcons.shieldCheck,
          iconColor: AppTheme.accent,
          iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
          title: 'Seller Verification',
          subtitle: 'Verify your identity to start selling',
          onTap: () => Navigator.of(context).pushNamed('/seller-profile-verification'),
        ),
        SizedBox(height: context.rh(8)),
        _GeneralLinkRow(
          icon: LucideIcons.info,
          iconColor: AppTheme.successMoss,
          iconBgColor: AppTheme.successMoss.withValues(alpha: 0.1),
          title: 'About Instiy',
          subtitle: 'Learn more about the platform',
          onTap: () => Navigator.of(context).pushNamed('/about'),
        ),
        SizedBox(height: context.rh(8)),
        _GeneralLinkRow(
          icon: LucideIcons.shield,
          iconColor: AppTheme.accent,
          iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
          title: 'Privacy Policy',
          subtitle: 'How we handle your data',
          onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
        ),
        SizedBox(height: context.rh(8)),
        _GeneralLinkRow(
          icon: LucideIcons.fileText,
          iconColor: AppTheme.accent,
          iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
          title: 'Terms & Conditions',
          subtitle: 'Rules for using Instiy',
          onTap: () => Navigator.of(context).pushNamed('/terms-conditions'),
        ),
        SizedBox(height: context.rh(8)),
        _GeneralLinkRow(
          icon: LucideIcons.helpCircle,
          iconColor: AppTheme.mutedSteel,
          iconBgColor: AppTheme.mutedSteel.withValues(alpha: 0.1),
          title: 'FAQ',
          subtitle: 'Frequently asked questions',
          onTap: () => Navigator.of(context).pushNamed('/faq'),
        ),
        SizedBox(height: context.rh(32)),
      ],
    );
  }
}

class _GeneralLinkRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GeneralLinkRow({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.rr(12)),
        child: Container(
          padding: context.rAll(16),
          decoration: BoxDecoration(
            color: AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(context.rr(12)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: context.rAll(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(context.rr(12)),
                ),
                child: Icon(icon, color: iconColor, size: context.ri(22)),
              ),
              SizedBox(width: context.rw(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                    SizedBox(height: context.rh(2)),
                    Text(subtitle, style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: context.ri(18), color: AppTheme.mutedSteel),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockScreenItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const _LockScreenItem({
    required this.icon,
    required this.label,
    required this.detail,
    required this.enabled,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(6)),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.rw(12), vertical: context.rh(10)),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.05)
              : AppTheme.warmMist.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(context.rr(10)),
          border: Border.all(
            color: enabled
                ? AppTheme.accent.withValues(alpha: 0.15)
                : AppTheme.whisperBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: context.ri(18), color: enabled ? AppTheme.accent : AppTheme.mutedSteel),
            SizedBox(width: context.rw(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(
                    fontSize: context.rsp(13),
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppTheme.charcoalInk : AppTheme.mutedSteel,
                  )),
                  Text(detail, style: TextStyle(fontSize: context.rsp(11), color: AppTheme.mutedSteel)),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: AppTheme.accent,
            ),
          ],
        ),
      ),
    );
  }
}
