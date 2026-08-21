import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../services/wallet_service.dart';
import '../../services/business_profile_service.dart';
import '../../providers/providers.dart';
import '../../widgets/universal_scanner.dart';
import '../../utils/responsive.dart';

class WalletTagScreen extends ConsumerStatefulWidget {
  const WalletTagScreen({super.key});

  @override
  ConsumerState<WalletTagScreen> createState() => _WalletTagScreenState();
}

class _WalletTagScreenState extends ConsumerState<WalletTagScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isProcessing = false;
  String? _displayName;
  String? _avatarUrl;
  bool _isLoadingName = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild on tab change so the scanner is only mounted (and the camera only
    // running) while the "Send" tab is actually visible. This frees the camera
    // when the user is on "Receive" and avoids the camera silently running in
    // the background of an off-screen tab.
    _tabController.addListener(_onTabChanged);
    // Name/avatar can change via profile edits elsewhere — keep in sync
    ref.listenManual(authProvider, (previous, next) {
      _loadDisplayName();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDisplayName();
    });
  }

  void _onTabChanged() {
    // Only react when the index actually settles, not mid-swipe.
    if (!_tabController.indexIsChanging) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      final user = ref.read(authProvider).user;
      final userId = user?.id;
      if (userId == null) {
        setState(() {
          _isLoadingName = false;
        });
        return;
      }

      // Check if seller and has business name
      final profile = await BusinessProfileService.getProfile(userId);
      if (profile != null && profile.businessName != null && profile.businessName!.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _displayName = profile.businessName;
            _avatarUrl = user?.avatarUrl;
            _isLoadingName = false;
          });
          return;
        }
      }

      // Otherwise, get user's full name
      if (mounted) {
        setState(() {
          _displayName = user?.fullName;
          _avatarUrl = user?.avatarUrl;
          _isLoadingName = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingName = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<bool?> _showSendMoneyDialog(String recipientId, String recipientName) {
    final amountCtrl = TextEditingController();
    bool isSubmitting = false;

    return showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => ShadDialog(
          title: const Text('Send Money'),
          description: Text('Enter the amount you wish to transfer to $recipientName.'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: context.rh(16)),
              ShadInput(
                controller: amountCtrl,
                placeholder: const Text('Amount (GH₵)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                leading: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('GH₵', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                onChanged: (_) => setStateDialog(() {}),
              ),
              SizedBox(height: context.rh(24)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.ghost(
                    onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  SizedBox(width: context.rw(8)),
                  ShadButton(
                    enabled: (double.tryParse(amountCtrl.text.trim()) ?? 0) > 0,
                    onPressed: (isSubmitting || (double.tryParse(amountCtrl.text.trim()) ?? 0) <= 0)
                        ? null
                        : () async {
                            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                            if (amount <= 0) {
                              ShadToaster.of(ctx).show(
                                const ShadToast.destructive(
                                  title: Text('Invalid Amount'),
                                  description: Text('Please enter a valid transfer amount.'),
                                ),
                              );
                              return;
                            }

                            setStateDialog(() => isSubmitting = true);

                            try {
                              // Verify balance first
                              final hasBalance = await WalletService.checkBalance(amount);
                              if (!hasBalance) {
                                if (ctx.mounted) {
                                  ShadToaster.of(ctx).show(
                                    const ShadToast.destructive(
                                      title: Text('Insufficient Balance'),
                                      description: Text('You do not have enough funds for this transfer.'),
                                    ),
                                  );
                                  setStateDialog(() => isSubmitting = false);
                                }
                                return;
                              }

                              await WalletService.transferToUser(
                                recipientId: recipientId,
                                amount: amount,
                                description: 'QR Tag Transfer',
                              );

                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ShadToaster.of(ctx).show(
                                  ShadToast.destructive(
                                    title: const Text('Transfer Failed'),
                                    description: Text(e.toString()),
                                  ),
                                );
                                setStateDialog(() => isSubmitting = false);
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Send Funds'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Wallet Tag'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.paddingOf(context).top + kToolbarHeight + 10,
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.mutedSteel,
            indicatorColor: AppTheme.accent,
            tabs: const [
              Tab(icon: Icon(LucideIcons.qrCode), text: 'Receive'),
              Tab(icon: Icon(LucideIcons.scan), text: 'Send'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              // Disable swipe so the camera isn't half-initialised during a drag;
              // tab taps still work and give a clean mount/unmount of the scanner.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildReceiveTab(),
                // Only mount the live scanner when the Send tab is selected. When the
                // user is on Receive, this returns a lightweight placeholder so the
                // camera is fully released instead of running off-screen.
                _tabController.index == 1
                    ? _buildSendTab()
                    : const _ScannerPlaceholder(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    final userId = SupabaseService.auth.currentUser?.id ?? '';
    final qrData = 'instiy:pay:$userId';
    final user = ref.read(authProvider).user;
    final cleanedTag = user?.walletTag ?? '';

    return Container(
      color: AppTheme.canvasWhite,
      child: Center(
        child: RefreshIndicator(
          onRefresh: _loadDisplayName,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // White QR card matching screenshot layout
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: context.rw(240),
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Colors.black,
                      ),
                      embeddedImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(_avatarUrl!)
                          : const AssetImage('assets/logo_highres.png') as ImageProvider,
                      embeddedImageStyle: const QrEmbeddedImageStyle(
                        size: Size(48, 48),
                      ),
                    ),
                    // Beautiful centered logo container with spacing, border, and shadow
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _avatarUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Image.asset('assets/logo_highres.png'),
                                errorWidget: (_, _, _) => Image.asset('assets/logo_highres.png'),
                              )
                            : Image.asset(
                                'assets/logo_highres.png',
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.rh(32)),
              // Name and Tag section below the QR code card
              if (_isLoadingName)
                const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              else if (_displayName != null) ...[
                Text(
                  _displayName!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(26),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'Scan to pay \$$cleanedTag',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(15),
                    color: AppTheme.mutedSteel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendTab() {
    return UniversalScanner(
      title: 'Scan to Send',
      subtitle: 'Align the QR code within the frame',
      cutOutSize: context.rw(250),
      onDetect: (code) async {
        if (_isProcessing) return;

        // We expect the QR code to be in format: "instiy:pay:<user_id>"
        if (code.startsWith('instiy:pay:')) {
          setState(() {
            _isProcessing = true;
          });

          final recipientId = code.replaceFirst('instiy:pay:', '');
          if (!mounted) return;

          // Look up recipient info
          String recipientName = 'User';
          try {
            final recipientUser = await SupabaseService.client
                .from('users')
                .select('full_name')
                .eq('id', recipientId)
                .maybeSingle();

            final recipientBiz = await SupabaseService.client
                .from('business_profiles')
                .select('business_name')
                .eq('seller_id', recipientId)
                .maybeSingle();

            recipientName = recipientBiz?['business_name'] as String? ?? 
                            recipientUser?['full_name'] as String? ?? 
                            'User';
          } catch (_) {}

          if (!mounted) return;

          // Show amount dialog
          final success = await _showSendMoneyDialog(recipientId, recipientName);

          if (mounted) {
            if (success == true) {
              Navigator.of(context).pop(); // Close scanner
              ShadToaster.of(context).show(
                const ShadToast(
                  title: Text('Transfer Successful'),
                  description: Text('Funds have been sent to the user.'),
                ),
              );
            } else {
              setState(() {
                _isProcessing = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _isProcessing = true;
            });

            ShadToaster.of(context).show(
              const ShadToast.destructive(
                title: Text('Invalid QR Code'),
                description: Text('This QR code does not belong to an Instiy user.'),
              ),
            );

            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _isProcessing = false;
                });
              }
            });
          }
        }
      },
    );
  }
}

/// Lightweight stand-in shown on the Send tab while it is NOT selected, so the
/// camera is never initialised behind the scenes. Tapping prompts the user to
/// switch to the Send tab (which then mounts the real scanner).
class _ScannerPlaceholder extends StatelessWidget {
  const _ScannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.scanLine, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text(
              'Tap the Send tab to scan',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
