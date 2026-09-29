import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/providers.dart';
import '../../models/wallet_model.dart';
import '../../utils/responsive.dart';
import '../../utils/formatters.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../widgets/required_label.dart';
import '../../widgets/skeleton.dart';
import '../../services/wallet_service.dart';
import '../../services/seller_service.dart';
import '../../services/supabase_service.dart';
import '../../services/wallet_lock_service.dart';
import '../seller/scanner_screen.dart';
import 'wallet_tag_screen.dart';
import 'transaction_detail_screen.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isLocked = true;
  bool _checkingLock = true;
  bool _hasPushedOver = false;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLock();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(walletProvider).loadMoreTransactions();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {}); // Show/hide clear button immediately
    // Filtering is client-side over the loaded transactions — instant, no
    // reload of the wallet data.
    ref.read(walletProvider).setSearchQuery(query);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _hasPushedOver = true;
    } else if (route != null && route.isCurrent && _hasPushedOver) {
      _hasPushedOver = false;
      if (!_isLocked && mounted) {
        ref.read(walletProvider).silentRefresh();
      }
    }
  }

  Future<void> _checkLock() async {
    final shouldAuth = await WalletLockService.unlockIfNeeded(
      reason: 'Authenticate to access your wallet',
    );
    if (!mounted) return;
    if (shouldAuth) {
      setState(() {
        _isLocked = false;
        _checkingLock = false;
      });
      unawaited(ref.read(walletProvider).loadWallet());
    } else {
      setState(() {
        _isLocked = true;
        _checkingLock = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletProv = ref.watch(walletProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Wallet')),
        body: const Center(child: Text('Sign in to view your wallet')),
      );
    }

    if (_checkingLock) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Wallet')),
        body: Padding(
          padding: context.rAll(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance card skeleton
              Skeleton(
                width: double.infinity,
                height: context.rh(120),
                borderRadius: BorderRadius.circular(context.rr(16)),
              ),
              SizedBox(height: context.rh(20)),
              // Action buttons skeleton
              Row(
                children: [
                  Expanded(child: Skeleton(width: double.infinity, height: context.rh(44), borderRadius: BorderRadius.circular(context.rr(12)))),
                  SizedBox(width: context.rw(12)),
                  Expanded(child: Skeleton(width: double.infinity, height: context.rh(44), borderRadius: BorderRadius.circular(context.rr(12)))),
                ],
              ),
              SizedBox(height: context.rh(24)),
              // Section title
              Skeleton(width: context.rw(120), height: context.rh(14)),
              SizedBox(height: context.rh(12)),
              // Transaction list
              const ListSkeleton(count: 5),
            ],
          ),
        ),
      );
    }

    if (_isLocked) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Wallet')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: context.rw(80),
                height: context.rh(80),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.lock, size: context.ri(40), color: AppTheme.accent),
              ),
              SizedBox(height: context.rh(16)),
              Text(
                'Wallet Locked',
                style: TextStyle(
                  fontSize: context.rsp(20),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(8)),
              Text(
                'Use your fingerprint or screen lock\nto access your wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              SizedBox(height: context.rh(24)),
              ShadButton(
                onPressed: () async {
                  final provider = ref.read(walletProvider);
                  final authed = await WalletLockService.authenticate(
                    reason: 'Authenticate to access your wallet',
                  );
                  if (authed && mounted) {
                    setState(() => _isLocked = false);
                    unawaited(provider.loadWallet());
                  }
                },
                leading: Icon(LucideIcons.fingerprint, size: context.ri(20)),
                child: const Text('Unlock Wallet'),
              ),
              SizedBox(height: context.rh(12)),
              ShadButton.ghost(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Wallet')),
      body: walletProv.isLoading
          ? SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 16, 16),
              child: Column(
                children: [
                  Skeleton(width: double.infinity, height: context.rh(160), borderRadius: BorderRadius.all(Radius.circular(context.rr(20)))),
                  SizedBox(height: context.rh(16)),
                  Row(
                    children: [
                      Expanded(child: Skeleton(width: context.rw(100), height: context.rh(50), borderRadius: BorderRadius.all(Radius.circular(context.rr(12))))),
                      SizedBox(width: context.rw(12)),
                      Expanded(child: Skeleton(width: context.rw(100), height: context.rh(50), borderRadius: BorderRadius.all(Radius.circular(context.rr(12))))),
                      SizedBox(width: context.rw(12)),
                      Expanded(child: Skeleton(width: context.rw(100), height: context.rh(50), borderRadius: BorderRadius.all(Radius.circular(context.rr(12))))),
                    ],
                  ),
                  SizedBox(height: context.rh(24)),
                  ListSkeleton(count: 6),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => walletProv.loadWallet(),
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 16, 16),
                children: [
                  _buildBalanceCard(walletProv),
                  SizedBox(height: context.rh(16)),
                  _buildActions(walletProv),
                  SizedBox(height: context.rh(24)),
                  Text(
                    'Transaction History',
                    style: TextStyle(
                      fontSize: context.rsp(18),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(12)),
                  _buildSearchInput(),
                  SizedBox(height: context.rh(12)),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'all', walletProv.filterType, (val) {
                          ref.read(walletProvider).setFilterType(val);
                        }),
                        SizedBox(width: context.rw(8)),
                        _buildFilterChip('Credits', 'credit', walletProv.filterType, (val) {
                          ref.read(walletProvider).setFilterType(val);
                        }),
                        SizedBox(width: context.rw(8)),
                        _buildFilterChip('Debits', 'debit', walletProv.filterType, (val) {
                          ref.read(walletProvider).setFilterType(val);
                        }),
                      ],
                    ),
                  ),
                  SizedBox(height: context.rh(16)),
                  if (walletProv.isLoading && walletProv.transactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (walletProv.filteredTransactions.isEmpty)
                    _buildEmptyTransactionsState(walletProv)
                  else ...[
                    ...walletProv.filteredTransactions.map(
                      (tx) => _TransactionTile(tx),
                    ),
                    if (walletProv.isLoadingMore)
                      Padding(
                        padding: context.rAll(16),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                  SizedBox(height: context.rh(80)),
                ],
              ),
            ),
    );
  }

  double _balanceFontSize(double amount) {
    final formatted = formatGhs(amount);
    final len = formatted.length;
    if (len <= 10) return 36;
    if (len <= 13) return 30;
    if (len <= 16) return 24;
    return 20;
  }

  Widget _buildBalanceCard(WalletProvider provider) {
    return Container(
      padding: context.rAll(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.9),
            AppTheme.accent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(context.rr(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Balance',
            style: TextStyle(color: Colors.white70, fontSize: context.rsp(14)),
          ),
          SizedBox(height: context.rh(8)),
          Text(
            formatGhs(provider.availableBalance),
            style: TextStyle(
              color: Colors.white,
              fontSize: context.rsp(_balanceFontSize(provider.availableBalance)),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: context.rh(16)),
          Row(
            children: [
              _BalanceStat(
                label: 'Total',
                value: formatGhs(provider.wallet?.balance ?? 0),
              ),
              SizedBox(width: context.rw(24)),
              _BalanceStat(
                label: 'Pending',
                value: formatGhs(provider.pendingBalance),
                color: Colors.amberAccent,
                onTap: () => _showPendingBreakdown(context, provider),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPendingBreakdown(BuildContext context, WalletProvider provider) {
    showShadSheet(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final liveProvider = ref.watch(walletProvider);
          final withdrawals = liveProvider.pendingWithdrawals;
          final earnings = liveProvider.pendingOrderEarnings;
          return ShadSheet(
            title: const Text('Pending Balance'),
            description: Text(
              '${formatGhs(liveProvider.pendingBalance)} not yet available — withdrawal holds and order earnings awaiting delivery.',
            ),
            child: withdrawals.isEmpty && earnings.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: context.rh(24)),
                    child: Center(
                      child: Text(
                        'No pending activities.\nYour full balance is available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.mutedSteel,
                          fontSize: context.rsp(13),
                        ),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The sheet's child scrolls as a whole, so no inner
                      // viewport here — a ListView would get unbounded height.
                      if (earnings.isNotEmpty) ...[
                        _buildSectionHeader(
                          'Order earnings awaiting delivery (${earnings.length})',
                        ),
                        ...earnings.map(_buildPendingEarningCard),
                        SizedBox(height: context.rh(16)),
                      ],
                      if (withdrawals.isNotEmpty) ...[
                        _buildSectionHeader(
                          'Withdrawals in progress (${withdrawals.length})',
                        ),
                        ...withdrawals.map(_buildPendingWithdrawalCard),
                        SizedBox(height: context.rh(12)),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total pending',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.rsp(14),
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          Text(
                            formatGhs(liveProvider.pendingBalance),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: context.rsp(15),
                              color: AppTheme.warningAmber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.rh(8)),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: context.rsp(12),
          color: AppTheme.mutedSteel,
        ),
      ),
    );
  }

  Widget _buildPendingEarningCard(PendingOrderEarning e) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDeliveryConfirmationOptions(context, e),
        borderRadius: BorderRadius.circular(context.rr(12)),
        child: Container(
          margin: EdgeInsets.only(bottom: context.rh(8)),
          padding: context.rAll(12),
          decoration: BoxDecoration(
            color: AppTheme.warmMist,
            borderRadius: BorderRadius.circular(context.rr(12)),
            border: Border.all(color: AppTheme.whisperBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(context.rr(10)),
                child: (e.productThumbnail != null &&
                        e.productThumbnail!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: e.productThumbnail!,
                        width: context.rw(46),
                        height: context.rw(46),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: context.rw(46),
                          height: context.rw(46),
                          color: AppTheme.whisperBorder.withValues(alpha: 0.3),
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (_, _, _) =>
                            _buildFallbackProductIcon(),
                      )
                    : _buildFallbackProductIcon(),
              ),
              SizedBox(width: context.rw(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.productTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.rsp(13),
                        color: AppTheme.charcoalInk,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: context.rh(2)),
                    Text(
                      'Tap to confirm delivery • ${DateFormat('MMM d, yyyy').format(e.createdAt)}',
                      style: TextStyle(
                        fontSize: context.rsp(11),
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: context.rw(8)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatGhs(e.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: context.rsp(13),
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(2)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.scanLine,
                        size: context.ri(11),
                        color: AppTheme.accent,
                      ),
                      SizedBox(width: context.rw(3)),
                      Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: context.rsp(10),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackProductIcon() {
    return Container(
      width: context.rw(46),
      height: context.rw(46),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.rr(10)),
      ),
      child: Icon(
        LucideIcons.package,
        color: AppTheme.accent,
        size: context.ri(20),
      ),
    );
  }

  void _showDeliveryConfirmationOptions(
    BuildContext context,
    PendingOrderEarning earning,
  ) {
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Confirm Delivery'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: context.rAll(10),
            decoration: BoxDecoration(
              color: AppTheme.warmMist,
              borderRadius: BorderRadius.circular(context.rr(12)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(context.rr(8)),
                  child: (earning.productThumbnail != null &&
                          earning.productThumbnail!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: earning.productThumbnail!,
                          width: context.rw(44),
                          height: context.rw(44),
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            width: context.rw(44),
                            height: context.rw(44),
                            color:
                                AppTheme.whisperBorder.withValues(alpha: 0.3),
                          ),
                          errorWidget: (_, _, _) =>
                              _buildFallbackProductIcon(),
                        )
                      : _buildFallbackProductIcon(),
                ),
                SizedBox(width: context.rw(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        earning.productTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: context.rsp(13),
                          color: AppTheme.charcoalInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: context.rh(2)),
                      Text(
                        'Releases ${formatGhs(earning.amount)} to wallet',
                        style: TextStyle(
                          fontSize: context.rsp(11),
                          color: AppTheme.successMoss,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.rh(16)),
          Text(
            'Confirm delivery with the buyer to release escrow funds:',
            style: TextStyle(
              fontSize: context.rsp(12),
              color: AppTheme.mutedSteel,
            ),
          ),
          SizedBox(height: context.rh(12)),
          // Option 1: Scan QR Code
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _scanDeliveryQrForEarning(earning);
              },
              borderRadius: BorderRadius.circular(context.rr(12)),
              child: Container(
                padding: context.rAll(12),
                decoration: BoxDecoration(
                  color: AppTheme.pureSurface,
                  borderRadius: BorderRadius.circular(context.rr(12)),
                  border: Border.all(color: AppTheme.whisperBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: context.rAll(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(context.rr(10)),
                      ),
                      child: Icon(
                        LucideIcons.scanLine,
                        color: AppTheme.accent,
                        size: context.ri(20),
                      ),
                    ),
                    SizedBox(width: context.rw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan QR Code',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.rsp(13),
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          Text(
                            'Scan buyer\'s delivery QR code',
                            style: TextStyle(
                              fontSize: context.rsp(11),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: context.ri(16),
                      color: AppTheme.mutedSteel,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: context.rh(8)),
          // Option 2: Enter Delivery Code
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _showManualDeliveryCodeDialog(earning);
              },
              borderRadius: BorderRadius.circular(context.rr(12)),
              child: Container(
                padding: context.rAll(12),
                decoration: BoxDecoration(
                  color: AppTheme.pureSurface,
                  borderRadius: BorderRadius.circular(context.rr(12)),
                  border: Border.all(color: AppTheme.whisperBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: context.rAll(8),
                      decoration: BoxDecoration(
                        color: AppTheme.successMoss.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(context.rr(10)),
                      ),
                      child: Icon(
                        LucideIcons.keyboard,
                        color: AppTheme.successMoss,
                        size: context.ri(20),
                      ),
                    ),
                    SizedBox(width: context.rw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter Delivery Code',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.rsp(13),
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          Text(
                            'Type 6-character code from buyer',
                            style: TextStyle(
                              fontSize: context.rsp(11),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: context.ri(16),
                      color: AppTheme.mutedSteel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _scanDeliveryQrForEarning(PendingOrderEarning earning) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          autoClose: true,
          title: 'Scan Delivery QR',
          subtitle: 'Point camera at buyer QR or product delivery code',
        ),
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _verifyDeliveryCode(earning, code.trim());
  }

  void _showManualDeliveryCodeDialog(PendingOrderEarning earning) {
    final codeController = TextEditingController();
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Enter Delivery Code'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the 6-character delivery code provided by the buyer for "${earning.productTitle}".',
              style: TextStyle(
                fontSize: context.rsp(13),
                color: AppTheme.mutedSteel,
              ),
            ),
            SizedBox(height: context.rh(16)),
            ShadInput(
              controller: codeController,
              placeholder: const Text('e.g. X7K9M2'),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: TextStyle(
                fontSize: context.rsp(22),
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AnimatedBuilder(
          animation: codeController,
          builder: (dialogCtx, _) {
            final canVerify = codeController.text.trim().isNotEmpty;
            return ShadButton(
              backgroundColor: AppTheme.successMoss,
              foregroundColor: Colors.white,
              enabled: canVerify,
              onPressed: canVerify
                  ? () {
                      final enteredCode = codeController.text.trim();
                      Navigator.of(dialogCtx).pop();
                      _verifyDeliveryCode(earning, enteredCode);
                    }
                  : null,
              child: const Text('Verify'),
            );
          },
        ),
      ],
    );
  }

  Future<void> _verifyDeliveryCode(
    PendingOrderEarning earning,
    String rawCode,
  ) async {
    final normalized = rawCode.replaceAll(RegExp(r'\s+'), '');
    const gqrPrefix = 'instiy-gqr:';

    try {
      Map<String, dynamic> result;
      if (normalized.toLowerCase().startsWith(gqrPrefix)) {
        final buyerId = normalized.substring(gqrPrefix.length);
        result = await SellerService.verifyBuyerDeliveries(
          buyerId,
          [earning.orderItemId],
        );
      } else {
        String cleanCode = normalized;
        if (cleanCode.toLowerCase().startsWith('instiy-code:')) {
          cleanCode = cleanCode.substring('instiy-code:'.length);
        } else if (cleanCode.toLowerCase().startsWith('instiy-item:')) {
          cleanCode = cleanCode.substring('instiy-item:'.length);
        } else if (cleanCode.toLowerCase().startsWith('code:')) {
          cleanCode = cleanCode.substring('code:'.length);
        }
        cleanCode = cleanCode.toUpperCase();
        result = await SellerService.verifyDelivery(
          earning.orderItemId,
          cleanCode,
        );
      }

      if (!mounted) return;

      if (result['success'] == true) {
        final amount =
            (result['amount'] as num?)?.toDouble() ?? earning.amount;
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.successMoss,
            title: Text(
              'Verified! ${formatGhs(amount)} released to wallet.',
            ),
          ),
        );
        await ref.read(walletProvider).loadWallet();
      } else {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text(result['error'] as String? ?? 'Verification failed'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Error verifying delivery: $e'),
        ),
      );
    }
  }

  Widget _buildPendingWithdrawalCard(WithdrawalRequest w) {
    final isProcessing = w.status == 'processing';
    return Container(
      margin: EdgeInsets.only(bottom: context.rh(8)),
      padding: context.rAll(12),
      decoration: BoxDecoration(
        color: AppTheme.warmMist,
        borderRadius: BorderRadius.circular(context.rr(12)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: context.rAll(8),
            decoration: BoxDecoration(
              color: AppTheme.warningAmber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(
              LucideIcons.arrowUp,
              color: AppTheme.warningAmber,
              size: context.ri(18),
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Withdrawal • ${w.methodType}${w.providerType != null && w.providerType!.isNotEmpty ? ' • ${w.providerType}' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.rsp(13),
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(2)),
                Text(
                  DateFormat('MMM d, yyyy • h:mm a').format(w.createdAt),
                  style: TextStyle(
                    fontSize: context.rsp(11),
                    color: AppTheme.mutedSteel,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatGhs(w.amountRequested),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.rsp(13),
                  color: AppTheme.charcoalInk,
                ),
              ),
              SizedBox(height: context.rh(4)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(8),
                  vertical: context.rh(2),
                ),
                decoration: BoxDecoration(
                  color: isProcessing
                      ? AppTheme.accent.withValues(alpha: 0.12)
                      : AppTheme.warningAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(context.rr(20)),
                ),
                child: Text(
                  isProcessing ? 'Processing' : 'Pending',
                  style: TextStyle(
                    fontSize: context.rsp(10),
                    fontWeight: FontWeight.w600,
                    color: isProcessing
                        ? AppTheme.accent
                        : AppTheme.warningAmber,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions(WalletProvider provider) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: LucideIcons.plus,
            label: 'Deposit',
            color: AppTheme.accent,
            onTap: () => _showDepositDialog(context),
          ),
        ),
        SizedBox(width: context.rw(12)),
        Expanded(
          child: _ActionButton(
            icon: LucideIcons.arrowUp,
            label: 'Withdraw',
            color: AppTheme.warningAmber,
            onTap: () => _showWithdrawDialog(context, provider),
          ),
        ),
        SizedBox(width: context.rw(12)),
        Expanded(
          child: _ActionButton(
            icon: LucideIcons.arrowLeftRight,
            label: 'Transfer',
            color: const Color(0xFF4D7C59),
            onTap: () => _showTransferDialog(context, provider),
          ),
        ),
        SizedBox(width: context.rw(12)),
        Expanded(
          child: _ActionButton(
            icon: LucideIcons.qrCode,
            label: 'Tag',
            color: const Color(0xFF0F766E),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletTagScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, String currentValue, ValueChanged<String> onTap) {
    final isSelected = value == currentValue;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : AppTheme.glassSurfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.charcoalInk,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput() {
    return ShadInput(
      controller: _searchController,
      placeholder: const Text('Search transactions...'),
      leading: const Padding(
        padding: EdgeInsets.only(left: 8, right: 8),
        child: Icon(LucideIcons.search, size: 16),
      ),
      trailing: _searchController.text.isNotEmpty
          ? GestureDetector(
              onTap: () {
                _searchController.clear();
                ref.read(walletProvider).setSearchQuery('');
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(LucideIcons.x, size: 16),
              ),
            )
          : null,
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildEmptyTransactionsState(WalletProvider provider) {
    final hasFilter = provider.searchQuery.isNotEmpty || provider.filterType != 'all';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilter ? LucideIcons.searchCode : LucideIcons.receipt,
              size: context.ri(48),
              color: Colors.grey[300],
            ),
            SizedBox(height: context.rh(12)),
            Text(
              hasFilter ? 'No matching transactions' : 'No transactions yet',
              style: TextStyle(
                fontSize: context.rsp(15),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            if (hasFilter) ...[
              SizedBox(height: context.rh(8)),
              Text(
                'Try clearing your search or filter.',
                style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDepositDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    AppTheme.showGlassDialog(
      context: context,
      title: const Text('Deposit Funds'),
      description: const Text('Fund your wallet via Paystack (card, mobile money, or bank).'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ShadInputFormField(
          id: 'deposit-amount',
          controller: amountCtrl,
          label: RequiredLabel('Amount (GHS)'),
          placeholder: const Text('Enter amount'),
          leading: const Text('GH\u00a2 '),
          keyboardType: TextInputType.number,
        ),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AnimatedBuilder(
          animation: amountCtrl,
          builder: (_, _) {
            final amountValid = (double.tryParse(amountCtrl.text.trim()) ?? 0) > 0;
            return ShadButton(
              enabled: amountValid,
              onPressed: amountValid
                  ? () async {
                      final amountText = amountCtrl.text.trim();
                      final amount = double.tryParse(amountText);
                      if (amount == null || amount <= 0) {
                        ShadToaster.of(context).show(
                          const ShadToast(title: Text('Enter a valid amount')),
                        );
                        return;
                      }

                      Navigator.of(context).pop();

                      final provider = ref.read(walletProvider);
                      final error = await provider.fundWalletWithPaystack(amount);

                      if (!context.mounted) return;

                      ShadToaster.of(context).show(
                        ShadToast(title: Text(error ?? 'Wallet funded successfully!')),
                      );
                    }
                  : null,
              child: const Text('Deposit'),
            );
          },
        ),
      ],
    );
  }

  void _showWithdrawDialog(BuildContext context, WalletProvider provider) {
    final amountCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String method = 'mobile_money';
    String? selectedProvider;
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    final mobileMoneyProviders = [
      {'name': 'MTN MoMo', 'value': 'MTN', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/9/93/New-mtn-logo.jpg'},
      {'name': 'Telecel Cash', 'value': 'Telecel', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/e/e3/Telecel_Group_Logo.png'},
      {'name': 'AT Money', 'value': 'AT', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/c/c5/Airtel_logo.png'},
    ];

    final bankProviders = [
      {'name': 'GCB Bank', 'value': 'GCB Bank', 'logo': 'https://www.gcbbank.com.gh/templates/rt_galatea/images/logo/logo-dark.png'},
      {'name': 'Ecobank', 'value': 'Ecobank', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/Ecobank_logo.svg/1280px-Ecobank_logo.svg.png'},
      {'name': 'Fidelity Bank', 'value': 'Fidelity Bank', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/87/Fidelity_Investments_Logo.svg/1280px-Fidelity_Investments_Logo.svg.png'},
      {'name': 'Stanbic Bank', 'value': 'Stanbic Bank', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/61/Standard_Bank_Logo.svg/1024px-Standard_Bank_Logo.svg.png'},
      {'name': 'Absa Bank', 'value': 'Absa Bank', 'logo': 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e7/Absa_Group_Limited_Logo.svg/1024px-Absa_Group_Limited_Logo.svg.png'},
    ];

    Widget buildProviderLogo(String? logoUrl, String providerName) {
      if (logoUrl != null && logoUrl.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            height: 20,
            width: 20,
            fit: BoxFit.cover,
            memCacheWidth: 20,
            placeholder: (context, url) => Container(
              height: 20,
              width: 20,
              color: AppTheme.warmMist,
              child: const Center(
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 20,
              width: 20,
              color: AppTheme.warmMist,
              child: Center(
                child: Text(
                  providerName.isNotEmpty ? providerName[0].toUpperCase() : 'B',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.mutedSteel),
                ),
              ),
            ),
          ),
        );
      }
      return Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: AppTheme.warmMist,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            providerName.isNotEmpty ? providerName[0].toUpperCase() : 'B',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.mutedSteel),
          ),
        ),
      );
    }

    AppTheme.showGlassDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          if (selectedProvider == null) {
            selectedProvider = method == 'mobile_money' ? 'MTN' : 'GCB Bank';
            providerCtrl.text = selectedProvider!;
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Withdraw Funds',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShadSelect<String>(
                        initialValue: method,
                        placeholder: const Text('Method'),
                        options: const [
                          ShadOption(value: 'mobile_money', child: Text('Mobile Money')),
                          ShadOption(value: 'bank', child: Text('Bank Transfer')),
                        ],
                        selectedOptionBuilder: (context, value) => Text(value == 'mobile_money' ? 'Mobile Money' : 'Bank Transfer'),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              method = val;
                              selectedProvider = val == 'mobile_money' ? 'MTN' : 'GCB Bank';
                              providerCtrl.text = selectedProvider!;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RequiredLabel(
                            method == 'mobile_money' ? 'Provider' : 'Bank Name',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ShadSelect<String>(
                            initialValue: selectedProvider,
                            placeholder: Text(method == 'mobile_money' ? 'Select Provider' : 'Select Bank'),
                            options: (method == 'mobile_money' ? mobileMoneyProviders : bankProviders).map((prov) {
                              return ShadOption(
                                value: prov['value']!,
                                child: Row(
                                  children: [
                                    buildProviderLogo(prov['logo'], prov['name']!),
                                    const SizedBox(width: 8),
                                    Text(prov['name']!),
                                  ],
                                ),
                              );
                            }).toList(),
                            selectedOptionBuilder: (context, value) {
                              final provs = method == 'mobile_money' ? mobileMoneyProviders : bankProviders;
                              final prov = provs.firstWhere((p) => p['value'] == value, orElse: () => provs.first);
                              return Row(
                                children: [
                                  buildProviderLogo(prov['logo'], prov['name']!),
                                  const SizedBox(width: 8),
                                  Text(prov['name']!),
                                ],
                              );
                            },
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  selectedProvider = val;
                                  providerCtrl.text = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ShadInputFormField(
                        id: 'withdraw-account',
                        controller: accountCtrl,
                        label: RequiredLabel(
                          method == 'mobile_money'
                              ? 'Mobile Money Number'
                              : 'Account Number',
                        ),
                        placeholder: const Text('Enter account'),
                        keyboardType: TextInputType.phone,
                        validator: (val) => val.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      ShadInputFormField(
                        id: 'withdraw-name',
                        controller: nameCtrl,
                        label: RequiredLabel('Account Name'),
                        placeholder: const Text('Enter account name'),
                        validator: (val) => val.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      ShadInputFormField(
                        id: 'withdraw-amount',
                        controller: amountCtrl,
                        label: RequiredLabel('Amount (GHS)'),
                        placeholder: const Text('Enter amount'),
                        leading: const Text('GH\u00a2 '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (val) {
                          if (val.trim().isEmpty) return 'Required';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      if (isSubmitting) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.ghost(
                    onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: Listenable.merge([accountCtrl, nameCtrl, amountCtrl]),
                    builder: (_, _) {
                      final formValid = accountCtrl.text.trim().isNotEmpty &&
                          nameCtrl.text.trim().isNotEmpty &&
                          (double.tryParse(amountCtrl.text.trim()) ?? 0) > 0;
                      return ShadButton(
                        enabled: formValid,
                        onPressed: (isSubmitting || !formValid)
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                final amt = double.parse(amountCtrl.text.trim());
                                final hasBalance = await WalletService.checkBalance(amt);
                                if (!hasBalance) {
                                  if (ctx.mounted) {
                                    ShadToaster.of(ctx).show(
                                      const ShadToast.destructive(
                                        title: Text('Insufficient Balance'),
                                        description: Text('You do not have enough funds for this withdrawal.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final authed = await WalletLockService.unlockIfNeeded(
                                  reason: 'Authenticate to confirm withdrawal',
                                );
                                if (!authed) return;
                                setState(() => isSubmitting = true);
                                try {
                                  final amt = double.parse(amountCtrl.text.trim());
                                  final fullDetails = '${nameCtrl.text.trim()} - ${accountCtrl.text.trim()}';
                                  await provider.requestWithdrawal(
                                    amount: amt,
                                    methodType: method,
                                    providerType: providerCtrl.text.trim(),
                                    accountDetails: fullDetails,
                                  );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (context.mounted) {
                                    ShadToaster.of(context).show(
                                      const ShadToast(title: Text('Withdrawal request submitted successfully!')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ShadToaster.of(context).show(
                                      ShadToast(title: Text('Error: $e')),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) setState(() => isSubmitting = false);
                                }
                              },
                        child: const Text('Submit'),
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTransferDialog(BuildContext context, WalletProvider provider) {
    final amountCtrl = TextEditingController();
    final recipientCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool isSearching = false;
    String? verifiedName;
    String? searchError;
    String? resolvedUuid;
    bool isSubmitting = false;

    AppTheme.showGlassDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transfer Funds',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Transfer balance instantly to another Instiy user using their email address.',
                style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: ShadInputFormField(
                              id: 'transfer-recipient',
                              controller: recipientCtrl,
                              label: RequiredLabel('Recipient Email or ID'),
                              placeholder: const Text('user@example.com'),
                              validator: (val) {
                                if (val.trim().isEmpty) return 'Required';
                                if (resolvedUuid == null) return 'Please verify recipient first';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ShadButton(
                              onPressed: isSearching
                                  ? null
                                  : () async {
                                      final query = recipientCtrl.text.trim();
                                      if (query.isEmpty) return;
                                      setState(() {
                                        isSearching = true;
                                        verifiedName = null;
                                        searchError = null;
                                        resolvedUuid = null;
                                      });
                                      try {
                                        final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
                                        if (uuidRegex.hasMatch(query)) {
                                          final user = await SupabaseService.client
                                              .from('users')
                                              .select('id, full_name')
                                              .eq('id', query)
                                              .maybeSingle();
                                          if (user != null) {
                                            setState(() {
                                              verifiedName = user['full_name'] as String?;
                                              resolvedUuid = user['id'] as String?;
                                            });
                                          } else {
                                            setState(() => searchError = 'User ID not found');
                                          }
                                        } else {
                                          final user = await SupabaseService.client
                                              .from('users')
                                              .select('id, full_name')
                                              .eq('email', query)
                                              .maybeSingle();
                                          if (user != null) {
                                            setState(() {
                                              verifiedName = user['full_name'] as String?;
                                              resolvedUuid = user['id'] as String?;
                                            });
                                          } else {
                                            setState(() => searchError = 'Email not found');
                                          }
                                        }
                                      } catch (e) {
                                        setState(() => searchError = 'Lookup failed');
                                      } finally {
                                        setState(() => isSearching = false);
                                      }
                                    },
                              child: isSearching
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Verify'),
                            ),
                          ),
                        ],
                      ),
                      if (verifiedName != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.successMoss.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.check, color: AppTheme.successMoss, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Recipient: $verifiedName',
                                  style: const TextStyle(
                                    color: AppTheme.successMoss,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (searchError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          searchError!,
                          style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ShadInputFormField(
                        id: 'transfer-amount',
                        controller: amountCtrl,
                        label: RequiredLabel('Amount (GHS)'),
                        placeholder: const Text('Enter amount'),
                        leading: const Text('GH\u00a2 '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (val) {
                          if (val.trim().isEmpty) return 'Required';
                          final amt = double.tryParse(val);
                          if (amt == null || amt <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      ShadInputFormField(
                        id: 'transfer-description',
                        controller: descriptionCtrl,
                        label: const Text('Description (Optional)'),
                        placeholder: const Text('e.g. Payment for service'),
                      ),
                      if (isSubmitting) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.ghost(
                    onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: amountCtrl,
                    builder: (_, _) {
                      final formValid = resolvedUuid != null &&
                          (double.tryParse(amountCtrl.text.trim()) ?? 0) > 0;
                      return ShadButton(
                        enabled: formValid,
                        onPressed: (isSubmitting || !formValid)
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                final amt = double.parse(amountCtrl.text.trim());
                                final hasBalance = await WalletService.checkBalance(amt);
                                if (!hasBalance) {
                                  if (ctx.mounted) {
                                    ShadToaster.of(ctx).show(
                                      const ShadToast.destructive(
                                        title: Text('Insufficient Balance'),
                                        description: Text('You do not have enough funds for this transfer.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final authed = await WalletLockService.unlockIfNeeded(
                                  reason: 'Authenticate to confirm transfer',
                                );
                                if (!authed) return;
                                setState(() => isSubmitting = true);
                                try {
                                  await provider.transferToUser(
                                    recipientId: resolvedUuid!,
                                    amount: amt,
                                    description: descriptionCtrl.text.trim().isNotEmpty
                                        ? descriptionCtrl.text.trim()
                                        : null,
                                  );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (context.mounted) {
                                    ShadToaster.of(context).show(
                                      const ShadToast(title: Text('Transfer completed successfully!')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ShadToaster.of(context).show(
                                      ShadToast(title: Text('Transfer failed: $e')),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) setState(() => isSubmitting = false);
                                }
                              },
                        child: const Text('Transfer'),
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  const _BalanceStat({
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  double _valueFontSize() {
    final len = value.length;
    if (len <= 10) return 14;
    if (len <= 13) return 12;
    if (len <= 16) return 11;
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: Colors.white60, fontSize: context.rsp(12))),
            if (onTap != null) ...[
              SizedBox(width: context.rw(4)),
              Icon(LucideIcons.info, size: context.ri(12), color: Colors.white60),
            ],
          ],
        ),
        SizedBox(height: context.rh(4)),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: context.rsp(_valueFontSize()),
            decoration: onTap != null ? TextDecoration.underline : null,
            decorationColor: Colors.white70,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rh(16)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: context.ri(28)),
            SizedBox(height: context.rh(6)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.rsp(12),
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final dynamic tx;

  const _TransactionTile(this.tx);

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(tx: tx as WalletTransaction),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.type == 'deposit' || tx.type == 'transfer_in';
    final icon = isCredit ? LucideIcons.arrowDown : LucideIcons.arrowUp;
    final color = isCredit ? AppTheme.successMoss : AppTheme.destructive;

    return Container(
      margin: EdgeInsets.only(bottom: context.rh(8)),
      padding: context.rAll(14),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(12)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: context.rAll(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(context.rr(10)),
            ),
            child: Icon(icon, color: color, size: context.ri(18)),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? tx.type.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(tx.createdAt),
                  style: TextStyle(fontSize: context.rsp(12), color: AppTheme.mutedSteel),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${formatGhs(tx.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(width: context.rw(8)),
          GestureDetector(
            onTap: () => _openDetails(context),
            child: Container(
              padding: context.rAll(6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.rr(8)),
              ),
              child: Icon(LucideIcons.info, color: AppTheme.accent, size: context.ri(16)),
            ),
          ),
        ],
      ),
    );
  }
}

