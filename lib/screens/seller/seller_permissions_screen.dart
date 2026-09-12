import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/email_service.dart';
import 'package:instiy/utils/formatters.dart';
import '../../utils/responsive.dart';
import '../product/product_detail_screen.dart';

/// Product title that opens [ProductDetailScreen] when tapped. Falls back to
/// plain text when no product id is available.
Widget _tappableProductTitle(
  BuildContext context,
  String title,
  String? productId, {
  double fontSize = 12,
}) {
  if (productId == null || productId.isEmpty || title.isEmpty) {
    return Text(
      title,
      style: TextStyle(fontSize: fontSize, color: AppTheme.mutedSteel),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
  return GestureDetector(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.accent.withValues(alpha: 0.4),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Icon(LucideIcons.chevronRight,
            size: fontSize, color: AppTheme.accent.withValues(alpha: 0.6)),
      ],
    ),
  );
}

class SellerPermissionsScreen extends ConsumerStatefulWidget {
  const SellerPermissionsScreen({super.key});

  @override
  ConsumerState<SellerPermissionsScreen> createState() =>
      _SellerPermissionsScreenState();
}

class _SellerPermissionsScreenState
    extends ConsumerState<SellerPermissionsScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _searching = false;
  final ScrollController _historyScrollController = ScrollController();
  final ScrollController _pendingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _historyScrollController.addListener(_onHistoryScroll);
    _pendingScrollController.addListener(_onPendingScroll);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _historyScrollController.removeListener(_onHistoryScroll);
    _pendingScrollController.removeListener(_onPendingScroll);
    _historyScrollController.dispose();
    _pendingScrollController.dispose();
    _focusNode.dispose();

    final controller = _codeController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    super.dispose();
  }

  void _onCodeChanged() {
    final text = _codeController.text.trim();
    if (text.length == 6 && !_searching) {
      _lookupCode(text);
    }
  }

  void _onHistoryScroll() {
    if (_historyScrollController.position.pixels >=
        _historyScrollController.position.maxScrollExtent - 200) {
      final sellerId = ref.read(authProvider).user?.id;
      if (sellerId != null) {
        ref
            .read(purchasePermissionProvider.notifier)
            .loadMorePermissionHistory(sellerId);
      }
    }
  }

  void _onPendingScroll() {
    if (_pendingScrollController.position.pixels >=
        _pendingScrollController.position.maxScrollExtent - 200) {
      final sellerId = ref.read(authProvider).user?.id;
      if (sellerId != null) {
        ref
            .read(purchasePermissionProvider.notifier)
            .loadMorePendingPermissions(sellerId);
      }
    }
  }

  Future<void> _lookupCode(String code) async {
    setState(() => _searching = true);
    _focusNode.unfocus();

    final provider = ref.read(purchasePermissionProvider);
    await provider.lookupCode(code);

    if (mounted) {
      setState(() => _searching = false);
      if (provider.errorMessage != null) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Lookup Failed'),
            description: Text(provider.errorMessage!),
          ),
        );
      }
    }
  }

  Future<void> _grantPermission(String permissionId, Duration expiry) async {
    final provider = ref.read(purchasePermissionProvider);
    final success = await provider.grantAccess(permissionId, expiry: expiry);

    if (mounted) {
      if (success) {
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('Access Granted Successfully'),
            description: Text(
                'The buyer can now purchase the product. This permission will expire in ${EmailService.formatPermissionDuration(expiry)}.'),
          ),
        );
      } else {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Grant Failed'),
            description: Text(provider.errorMessage ?? 'An error occurred.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(
          context: context,
          title: const Text('Buyer Permissions'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(sigmaX: AppTheme.glassBlurHeavy, sigmaY: AppTheme.glassBlurHeavy),
                  inner: const ColorFilter.matrix(AppTheme.saturateMatrix),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.pureSurface.withValues(alpha: 0.7),
                    border: Border(bottom: BorderSide(color: AppTheme.whisperBorder, width: 0.5)),
                  ),
                  child: TabBar(
                    indicatorColor: AppTheme.accent,
                    labelColor: AppTheme.accent,
                    unselectedLabelColor: AppTheme.mutedSteel,
                    labelStyle: TextStyle(fontSize: context.rsp(12), fontWeight: FontWeight.w600),
                    unselectedLabelStyle: TextStyle(fontSize: context.rsp(12), fontWeight: FontWeight.w500),
                    tabs: const [
                      Tab(text: 'Lookup'),
                      Tab(text: 'Pending'),
                      Tab(text: 'History'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _GrantAccessTab(
              codeController: _codeController,
              focusNode: _focusNode,
              searching: _searching,
              onLookup: _lookupCode,
              onGrant: _grantPermission,
              onClear: () {
                ref.read(purchasePermissionProvider).clearLookupResult();
                _codeController.clear();
                _focusNode.requestFocus();
              },
            ),
            _PendingTab(scrollController: _pendingScrollController),
            _HistoryTab(scrollController: _historyScrollController),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Grant Access Tab ─────────────────────────

class _GrantAccessTab extends ConsumerWidget {
  final TextEditingController codeController;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onLookup;
  final void Function(String permissionId, Duration expiry) onGrant;
  final VoidCallback onClear;

  const _GrantAccessTab({
    required this.codeController,
    required this.focusNode,
    required this.searching,
    required this.onLookup,
    required this.onGrant,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permState = ref.watch(purchasePermissionProvider);
    final lookupResult = permState.activeLookupResult;
    final isSearching = searching || permState.isLoading;

        final customer =
            lookupResult?['customer'] as Map<String, dynamic>?;
        final product =
            lookupResult?['product'] as Map<String, dynamic>?;

        final customerName =
            customer?['full_name'] as String? ?? 'Unknown Buyer';
        final customerAvatar = customer?['avatar_url'] as String?;
        final customerInstitution =
            customer?['university'] as String? ?? 'Unknown Institution';

        final productTitle = product?['title'] as String? ?? '';
        final productPrice =
            (product?['price'] as num?)?.toDouble() ?? 0.0;

        String? productThumbnail;
        final imageUrlsList = product?['image_urls'];
        if (product?['thumbnail_url'] != null) {
          productThumbnail = product!['thumbnail_url'] as String;
        } else if (imageUrlsList is List && imageUrlsList.isNotEmpty) {
          productThumbnail = imageUrlsList.first as String;
        }

        final permissionStatus = lookupResult?['status'] as String?;
        final expiresAtStr = lookupResult?['expires_at'] as String?;

        DateTime? expiresAt;
        if (expiresAtStr != null) {
          expiresAt = DateTime.tryParse(expiresAtStr);
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Grant Purchase Access',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter the 6-character access code sent by the customer to verify their details and grant them buy permission for 24 hours.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.mutedSteel,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Code input
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: codeController,
                      focusNode: focusNode,
                      placeholder: const Text(
                          'Enter 6-digit code (e.g. AB12XY)'),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                      onSubmitted: (val) {
                        if (val.trim().length == 6) {
                          onLookup(val.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedBuilder(
                    animation: codeController,
                    builder: (context, _) {
                      final codeValid =
                          codeController.text.trim().length == 6;
                      return ShadButton(
                        enabled: codeValid,
                        onPressed: (!isSearching && codeValid)
                            ? () {
                                final code = codeController.text.trim();
                                if (code.length == 6) {
                                  onLookup(code);
                                } else {
                                  ShadToaster.of(context).show(
                                    const ShadToast.destructive(
                                      title: Text('Invalid Code'),
                                      description: Text(
                                          'Code must be exactly 6 alphanumeric characters.'),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Verify'),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Results
              if (isSearching)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                            color: AppTheme.accent),
                        const SizedBox(height: 12),
                        Text(
                          'Retrieving permission details...',
                          style: TextStyle(
                              color: AppTheme.mutedSteel, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              else if (lookupResult != null)
                _PermissionResultCard(
                  code: codeController.text.toUpperCase(),
                  customerName: customerName,
                  customerAvatar: customerAvatar,
                  customerInstitution: customerInstitution,
                  productTitle: productTitle,
                  productId: product?['id'] as String?,
                  productPrice: productPrice,
                  productThumbnail: productThumbnail,
                  permissionStatus: permissionStatus,
                  expiresAt: expiresAt,
                  permissionId: lookupResult['id'] as String,
                  onGrant: onGrant,
                ),
            ],
          ),
        );
  }
}

// ───────────────────── Permission Result Card ─────────────────────

class _PermissionResultCard extends StatefulWidget {
  final String code;
  final String customerName;
  final String? customerAvatar;
  final String customerInstitution;
  final String productTitle;
  final String? productId;
  final double productPrice;
  final String? productThumbnail;
  final String? permissionStatus;
  final DateTime? expiresAt;
  final String permissionId;
  final void Function(String permissionId, Duration expiry) onGrant;

  const _PermissionResultCard({
    required this.code,
    required this.customerName,
    this.customerAvatar,
    required this.customerInstitution,
    required this.productTitle,
    this.productId,
    required this.productPrice,
    this.productThumbnail,
    this.permissionStatus,
    this.expiresAt,
    required this.permissionId,
    required this.onGrant,
  });

  @override
  State<_PermissionResultCard> createState() => _PermissionResultCardState();
}

class _PermissionResultCardState extends State<_PermissionResultCard> {
  Duration _selectedExpiry = const Duration(hours: 24);

  static const _expiryOptions = [
    ('1 hour', Duration(hours: 1)),
    ('6 hours', Duration(hours: 6)),
    ('12 hours', Duration(hours: 12)),
    ('24 hours', Duration(hours: 24)),
    ('48 hours', Duration(hours: 48)),
    ('72 hours', Duration(hours: 72)),
    ('7 days', Duration(days: 7)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.whisperBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code banner
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.key,
                    size: 14, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  'Code: ${widget.code}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Customer
          const Text(
            'Customer Credentials',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.mutedSteel,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ShadAvatar(
                (widget.customerAvatar != null && widget.customerAvatar!.isNotEmpty)
                    ? widget.customerAvatar
                    : null,
                size: const Size(60, 60),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  widget.customerName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(LucideIcons.graduationCap,
                            size: 14, color: AppTheme.mutedSteel),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.customerInstitution,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.mutedSteel,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: AppTheme.whisperBorder),
          const SizedBox(height: 20),

          // Product
          const Text(
            'Requested Product',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.mutedSteel,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.productThumbnail != null &&
                        widget.productThumbnail!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.productThumbnail!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: AppTheme.warmMist,
                        child: const Icon(LucideIcons.package,
                            color: AppTheme.mutedSteel),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tappableProductTitle(
                      context,
                      widget.productTitle,
                      widget.productId,
                      fontSize: 15,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatGhs(widget.productPrice),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: AppTheme.whisperBorder),
          const SizedBox(height: 20),

          // Status
          if (widget.permissionStatus == 'pending') ...[
            const Row(
              children: [
                Icon(LucideIcons.circleAlert,
                    size: 16, color: Colors.orange),
                SizedBox(width: 6),
                Text(
                  'Status: Pending Approval',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Expiry duration picker
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warmMist,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Permission Duration',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedSteel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _expiryOptions.map((opt) {
                      final isSelected = _selectedExpiry == opt.$2;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedExpiry = opt.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.accent.withValues(alpha: 0.12)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppTheme.accent : AppTheme.whisperBorder,
                            ),
                          ),
                          child: Text(
                            opt.$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppTheme.accent : AppTheme.charcoalInk,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: () => widget.onGrant(widget.permissionId, _selectedExpiry),
                child: const Text('Grant Purchase Permission'),
              ),
            ),
          ] else if (widget.permissionStatus == 'granted') ...[
            Row(
              children: [
                const Icon(LucideIcons.checkCircle2,
                    size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status: Access Granted (Active)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      if (widget.expiresAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Expires: ${DateFormat('yyyy-MM-dd HH:mm').format(widget.expiresAt!.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const Icon(LucideIcons.xCircle,
                    size: 16, color: AppTheme.destructive),
                const SizedBox(width: 6),
                Text(
                  'Status: ${widget.permissionStatus?.toUpperCase() ?? 'INACTIVE'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.destructive,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Pending Tab ─────────────────────────

class _PendingTab extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const _PendingTab({required this.scrollController});

  @override
  ConsumerState<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends ConsumerState<_PendingTab> {
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialLoaded) {
        _initialLoaded = true;
        final sellerId = ref.read(authProvider).user?.id;
        if (sellerId != null) {
          ref.read(purchasePermissionProvider.notifier).loadPendingPermissions(sellerId);
        }
      }
    });
  }

  static const _expiryOptions = [
    ('1 hour', Duration(hours: 1)),
    ('6 hours', Duration(hours: 6)),
    ('12 hours', Duration(hours: 12)),
    ('24 hours', Duration(hours: 24)),
    ('48 hours', Duration(hours: 48)),
    ('72 hours', Duration(hours: 72)),
    ('7 days', Duration(days: 7)),
  ];

  Future<void> _grantWithExpiry(String permissionId, Duration expiry) async {
    final provider = ref.read(purchasePermissionProvider.notifier);
    final success = await provider.grantAccess(permissionId, expiry: expiry);
    if (mounted && success) {
      ShadToaster.of(context).show(
        ShadToast(
          title: Text('Access granted for ${_expiryOptions.firstWhere((e) => e.$2 == expiry, orElse: () => ('24 hours', Duration(hours: 24))).$1}'),
        ),
      );
    }
  }

  Future<void> _cancelPermission(String permissionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Permission'),
        content: const Text('The buyer will be notified that their request was declined. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final provider = ref.read(purchasePermissionProvider.notifier);
    final success = await provider.cancelAccess(permissionId);
    if (mounted && success) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Permission request declined')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(purchasePermissionProvider);
    final pending = provider.pendingPermissions;
    final isLoading = provider.isLoadingPending;
    final hasMore = provider.hasMorePending;

    if (isLoading && pending.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + kTextTabBarHeight + 56),
          child: const CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    if (pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          final sellerId = ref.read(authProvider).user?.id;
          if (sellerId != null) {
            await ref.read(purchasePermissionProvider.notifier).loadPendingPermissions(sellerId);
          }
        },
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Center(
              child: Column(
                children: [
                  Icon(LucideIcons.inbox, size: 48, color: AppTheme.mutedSteel.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text('No pending requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk)),
                  const SizedBox(height: 6),
                  const Text(
                    'Permission requests from buyers will appear here.',
                    style: TextStyle(fontSize: 13, color: AppTheme.mutedSteel),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final sellerId = ref.read(authProvider).user?.id;
        if (sellerId != null) {
          await ref.read(purchasePermissionProvider.notifier).loadPendingPermissions(sellerId);
        }
      },
      child: ListView.builder(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + kToolbarHeight + kTextTabBarHeight + 16, 20, 24),
        itemCount: pending.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == pending.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))),
            );
          }
          return _PendingPermissionTile(
            permission: pending[index],
            onGrant: _grantWithExpiry,
            onCancel: _cancelPermission,
          );
        },
      ),
    );
  }
}

// ───────────────────── Pending Permission Tile ─────────────────────

class _PendingPermissionTile extends StatefulWidget {
  final Map<String, dynamic> permission;
  final void Function(String permissionId, Duration expiry) onGrant;
  final ValueChanged<String> onCancel;

  const _PendingPermissionTile({
    required this.permission,
    required this.onGrant,
    required this.onCancel,
  });

  @override
  State<_PendingPermissionTile> createState() => _PendingPermissionTileState();
}

class _PendingPermissionTileState extends State<_PendingPermissionTile> {
  Duration _selectedExpiry = const Duration(hours: 24);

  static const _expiryOptions = [
    ('1h', Duration(hours: 1)),
    ('6h', Duration(hours: 6)),
    ('12h', Duration(hours: 12)),
    ('24h', Duration(hours: 24)),
    ('48h', Duration(hours: 48)),
    ('72h', Duration(hours: 72)),
    ('7d', Duration(days: 7)),
  ];

  @override
  Widget build(BuildContext context) {
    final customer = widget.permission['customer'] as Map<String, dynamic>?;
    final product = widget.permission['product'] as Map<String, dynamic>?;
    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final customerAvatar = customer?['avatar_url'] as String?;
    final customerInstitution = customer?['university'] as String? ?? '';
    final productTitle = product?['title'] as String? ?? '';
    final code = widget.permission['code'] as String? ?? '';
    final createdAtStr = widget.permission['created_at'] as String?;
    DateTime? createdAt;
    if (createdAtStr != null) createdAt = DateTime.tryParse(createdAtStr);

    String? productThumbnail;
    final imageUrlsList = product?['image_urls'];
    if (product?['thumbnail_url'] != null) {
      productThumbnail = product!['thumbnail_url'] as String;
    } else if (imageUrlsList is List && imageUrlsList.isNotEmpty) {
      productThumbnail = imageUrlsList.first as String;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: code + time
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.warningAmber, letterSpacing: 1.0)),
              ),
              const Spacer(),
              if (createdAt != null)
                Text(
                  DateFormat('MMM d, HH:mm').format(createdAt.toLocal()),
                  style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel.withValues(alpha: 0.6)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Buyer + product row
          Row(
            children: [
              ShadAvatar(
                (customerAvatar != null && customerAvatar.isNotEmpty) ? customerAvatar : null,
                size: const Size(36, 36),
                backgroundColor: AppTheme.accent,
                placeholder: Text(customerName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk), maxLines: 1, overflow: TextOverflow.ellipsis),
                    _tappableProductTitle(context, productTitle, product?['id'] as String?),
                    if (customerInstitution.isNotEmpty)
                      Text(customerInstitution, style: TextStyle(fontSize: 11, color: AppTheme.accent.withValues(alpha: 0.7)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (productThumbnail != null && productThumbnail.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: productThumbnail, width: 40, height: 40, fit: BoxFit.cover),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Expiry picker
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.warmMist, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Permission Duration', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _expiryOptions.map((opt) {
                    final isSelected = _selectedExpiry == opt.$2;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedExpiry = opt.$2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.accent.withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.whisperBorder),
                        ),
                        child: Text(opt.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? AppTheme.accent : AppTheme.charcoalInk)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ShadButton(
                  onPressed: () => widget.onGrant(widget.permission['id'] as String, _selectedExpiry),
                  child: const Text('Grant'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ShadButton.destructive(
                  onPressed: () => widget.onCancel(widget.permission['id'] as String),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── History Tab ─────────────────────────

class _HistoryTab extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const _HistoryTab({required this.scrollController});

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialLoaded) {
        _initialLoaded = true;
        final sellerId = ref.read(authProvider).user?.id;
        if (sellerId != null) {
          ref
              .read(purchasePermissionProvider.notifier)
              .loadPermissionHistory(sellerId);
        }
      }
    });
  }

  Future<void> _revokePermission(String permissionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Permission'),
        content: const Text(
            'The buyer will no longer be able to purchase this product and will be notified. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success =
        await ref.read(purchasePermissionProvider.notifier).revokeAccess(permissionId);
    if (mounted) {
      ShadToaster.of(context).show(
        ShadToast(
          title: Text(success ? 'Permission revoked' : 'Failed to revoke permission'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(purchasePermissionProvider);
    final history = provider.permissionHistory;
    final isLoading = provider.isLoadingHistory;
    final hasMore = provider.hasMoreHistory;

    if (isLoading && history.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 56),
          child: const CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    if (history.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          final sellerId = ref.read(authProvider).user?.id;
          if (sellerId != null) {
            await ref
                .read(purchasePermissionProvider.notifier)
                .loadPermissionHistory(sellerId);
          }
        },
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Center(
              child: Column(
                children: [
                  Icon(LucideIcons.history,
                      size: 48, color: AppTheme.mutedSteel.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text(
                    'No permission history',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Permissions you grant to buyers will appear here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedSteel,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final sellerId = ref.read(authProvider).user?.id;
        if (sellerId != null) {
          await ref
              .read(purchasePermissionProvider.notifier)
              .loadPermissionHistory(sellerId);
        }
      },
      child: ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + kToolbarHeight + 56,
        20,
        24,
      ),
      itemCount: history.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == history.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          );
        }
        return _HistoryPermissionTile(
          permission: history[index],
          sellerId: ref.read(authProvider).user?.id ?? '',
          onRevoke: _revokePermission,
        );
      },
      ),
    );
  }
}

// ───────────────────── History Tile ─────────────────────

class _HistoryPermissionTile extends StatelessWidget {
  final Map<String, dynamic> permission;
  final String sellerId;
  final ValueChanged<String>? onRevoke;

  const _HistoryPermissionTile({
    required this.permission,
    required this.sellerId,
    this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final customer =
        permission['customer'] as Map<String, dynamic>?;
    final product =
        permission['product'] as Map<String, dynamic>?;

    final customerName =
        customer?['full_name'] as String? ?? 'Unknown';
    final customerAvatar = customer?['avatar_url'] as String?;

    final productTitle = product?['title'] as String? ?? '';

    String? productThumbnail;
    final imageUrlsList = product?['image_urls'];
    if (product?['thumbnail_url'] != null) {
      productThumbnail = product!['thumbnail_url'] as String;
    } else if (imageUrlsList is List && imageUrlsList.isNotEmpty) {
      productThumbnail = imageUrlsList.first as String;
    }

    final status = permission['status'] as String? ?? 'unknown';
    final createdAtStr = permission['created_at'] as String?;
    final expiresAtStr = permission['expires_at'] as String?;

    DateTime? createdAt;
    DateTime? expiresAt;
    if (createdAtStr != null) createdAt = DateTime.tryParse(createdAtStr);
    if (expiresAtStr != null) expiresAt = DateTime.tryParse(expiresAtStr);

    // Only still-active grants can be revoked.
    final canRevoke = status == 'granted' &&
        onRevoke != null &&
        (expiresAt == null || expiresAt.isAfter(DateTime.now()));

    final code = permission['code'] as String? ?? '';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'granted':
        statusColor = Colors.green;
        statusIcon = LucideIcons.checkCircle2;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = LucideIcons.clock;
        break;
      case 'revoked':
        statusColor = AppTheme.destructive;
        statusIcon = LucideIcons.shieldOff;
        break;
      default:
        statusColor = AppTheme.destructive;
        statusIcon = LucideIcons.xCircle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.whisperBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: code + status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                status[0].toUpperCase() + status.substring(1),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Buyer row
          Row(
            children: [
              ShadAvatar(
                (customerAvatar != null && customerAvatar.isNotEmpty)
                    ? customerAvatar
                    : null,
                size: const Size(36, 36),
                backgroundColor: AppTheme.accent,
                placeholder: Text(
                  customerName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _tappableProductTitle(
                        context, productTitle, product?['id'] as String?),
                  ],
                ),
              ),
              if (productThumbnail != null && productThumbnail.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: productThumbnail,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Timestamps
          Row(
            children: [
              if (createdAt != null) ...[
                Icon(LucideIcons.calendar,
                    size: 12, color: AppTheme.mutedSteel.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, yyyy HH:mm').format(createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedSteel.withValues(alpha: 0.8),
                  ),
                ),
              ],
              const Spacer(),
              if (expiresAt != null)
                Text(
                  'Exp: ${DateFormat('MMM d HH:mm').format(expiresAt.toLocal())}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedSteel.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),

          // Revoke action for still-active grants.
          if (canRevoke) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => onRevoke!(permission['id'] as String),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.destructive.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.shieldOff,
                          size: 14, color: AppTheme.destructive),
                      const SizedBox(width: 6),
                      Text(
                        'Revoke Access',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.destructive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
