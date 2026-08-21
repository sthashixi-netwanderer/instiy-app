import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../services/sms_service.dart';
import '../../services/wallet_lock_service.dart';
import '../../services/paystack_service.dart';
import '../../models/institution_model.dart';
import '../../models/cart_model.dart';
import '../../services/institution_service.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';
import 'order_confirmation_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final Product? buyNowProduct;
  const CheckoutScreen({super.key, this.buyNowProduct});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _paymentMethod = 'wallet';
  String? _deliveryMode;
  bool _isProcessing = false;
  bool _orderPlaced = false;  // guard against cart-empty auto-pop race
  List<Institution> _institutions = [];
  Map<String, Product> _productsMap = {};
  String? _selectedDeliveryInstitution;
  int _buyNowQuantity = 1;

  bool get _isBuyNowMode => widget.buyNowProduct != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider).loadWallet();
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      final list = await InstitutionService.getInstitutions();
      final Map<String, Product> productsMap = {};

      if (_isBuyNowMode) {
        final product = widget.buyNowProduct!;
        productsMap[product.id] = product;
      } else {
        final cartItems = ref.read(cartProvider).cart.items;
        for (final item in cartItems) {
          final p = await ProductService.getProduct(item.productId);
          productsMap[item.productId] = p;
        }
      }
      if (mounted) {
        setState(() {
          _institutions = list;
          _productsMap = productsMap;

          // Automatically select customer's campus (only while nothing is
          // selected, so a manual choice survives pull-to-refresh)
          if (_selectedDeliveryInstitution == null) {
            final userUniv = ref.read(authProvider).user?.university;
            if (userUniv != null && userUniv.isNotEmpty) {
              final match = list.firstWhere(
                (inst) =>
                    inst.name.toLowerCase() == userUniv.toLowerCase() ||
                    inst.code.toLowerCase() == userUniv.toLowerCase(),
                orElse: () => Institution(id: '', code: '', name: ''),
              );
              if (match.name.isNotEmpty) {
                _selectedDeliveryInstitution = match.name;
              }
            }
          }
        });
      }
    } catch (_) {}
  }

  double _getDeliveryFeeForProduct(CartItem item, String? institutionName) {
    if (institutionName == null) return item.deliveryFee;
    final product = _productsMap[item.productId];
    if (product == null) return item.deliveryFee;

    if (product.institutionDeliveryFees.containsKey(institutionName)) {
      return product.institutionDeliveryFees[institutionName]!;
    }
    return product.deliveryFee;
  }

  double _getDeliveryFeeForBuyNow(String? institutionName) {
    final product = widget.buyNowProduct!;
    if (institutionName == null) return product.deliveryFee;
    if (product.institutionDeliveryFees.containsKey(institutionName)) {
      return product.institutionDeliveryFees[institutionName]!;
    }
    return product.deliveryFee;
  }

  @override
  Widget build(BuildContext context) {
    final cartProv = ref.watch(cartProvider);
    final authProv = ref.watch(authProvider);
    final walletProv = ref.watch(walletProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Checkout')),
        body: const Center(child: Text('Please sign in to checkout')),
      );
    }

    if (_isProcessing) {
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.accent,
          ),
        ),
      );
    }

    if (!_isBuyNowMode && cartProv.cart.items.isEmpty && !_isProcessing && !_orderPlaced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final walletBalance = walletProv.availableBalance;
    final cartItems = cartProv.cart.items;

    String? deliveryOption;
    if (_isBuyNowMode) {
      deliveryOption = widget.buyNowProduct!.deliveryOption;
    }

    final hasPickupOnly = _isBuyNowMode
        ? deliveryOption == 'pickup'
        : cartItems.any((item) {
            final product = _productsMap[item.productId];
            return product?.deliveryOption == 'pickup';
          });

    final hasDeliveryOnly = _isBuyNowMode
        ? deliveryOption == 'delivery'
        : cartItems.any((item) {
            final product = _productsMap[item.productId];
            return product?.deliveryOption == 'delivery';
          });

    final pickupEnabled = !hasDeliveryOnly;
    final deliveryEnabled = !hasPickupOnly;

    // Normalize active delivery mode based on availability of options
    if (_deliveryMode == null || (_deliveryMode == 'pickup' && !pickupEnabled) || (_deliveryMode == 'delivery' && !deliveryEnabled)) {
      if (pickupEnabled && !deliveryEnabled) {
        _deliveryMode = 'pickup';
        _selectedDeliveryInstitution = null;
      } else if (deliveryEnabled && !pickupEnabled) {
        _deliveryMode = 'delivery';
      }
    }

    final deliveryTotal = _isBuyNowMode
        ? (_deliveryMode == 'delivery' ? _getDeliveryFeeForBuyNow(_selectedDeliveryInstitution) : 0.0)
        : (_deliveryMode == 'delivery'
            ? cartItems.fold<double>(0.0, (sum, item) => sum + _getDeliveryFeeForProduct(item, _selectedDeliveryInstitution))
            : 0.0);
    final subtotal = _isBuyNowMode
        ? widget.buyNowProduct!.effectivePrice * _buyNowQuantity
        : cartProv.cart.subtotalAmount;
    final cartTotal = subtotal + deliveryTotal;
    final hasWalletBalance = walletBalance >= cartTotal;

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Checkout')),
      bottomNavigationBar: Container(
        padding: context.rAll(20),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
        ),
        child: SafeArea(
          child: AppButton(
            enabled: _deliveryMode != null &&
                (_deliveryMode != 'delivery' || _selectedDeliveryInstitution != null),
            onPressed: (_isProcessing ||
                    _deliveryMode == null ||
                    (_deliveryMode == 'delivery' && _selectedDeliveryInstitution == null))
                ? null
                : _openOrderConfirmation,
            loading: _isProcessing,
            child: Text('Place Order',
                style: TextStyle(fontSize: context.rsp(16), fontWeight: FontWeight.w600)),
          ),
        ),
      ),
      child: RefreshIndicator(
        // Only re-fetches reference data (institutions/product info);
        // form selections are kept intact.
        onRefresh: _loadData,
        child: ListView(
        padding: EdgeInsets.fromLTRB(context.rw(16), MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16), context.rw(16), context.rh(16)),
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
                Text(
                  'Order Summary',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(12)),
                if (_isBuyNowMode) ...[
                  // Buy Now mode: single product with quantity controls
                  Builder(
                    builder: (context) {
                      final product = widget.buyNowProduct!;
                      final itemDeliveryFee = _deliveryMode == 'delivery'
                          ? _getDeliveryFeeForBuyNow(_selectedDeliveryInstitution)
                          : 0.0;
                      final lineTotal = product.effectivePrice * _buyNowQuantity;
                      return Padding(
                        padding: context.rPadding(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    product.title,
                                    style: const TextStyle(color: AppTheme.charcoalInk),
                                  ),
                                ),
                                Text(
                                  formatGhs(lineTotal),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            if (product.stockQuantity > 1) ...[
                              SizedBox(height: context.rh(8)),
                              Row(
                                children: [
                                  Text(
                                    'Qty:',
                                    style: TextStyle(
                                      fontSize: context.rsp(13),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                  SizedBox(width: context.rw(8)),
                                  GestureDetector(
                                    onTap: _buyNowQuantity > 1
                                        ? () => setState(() => _buyNowQuantity--)
                                        : null,
                                    child: Container(
                                      width: context.rw(28),
                                      height: context.rh(28),
                                      decoration: BoxDecoration(
                                        color: _buyNowQuantity > 1
                                            ? AppTheme.accent.withValues(alpha: 0.1)
                                            : AppTheme.warmMist,
                                        borderRadius: BorderRadius.circular(context.rr(6)),
                                        border: Border.all(color: AppTheme.whisperBorder),
                                      ),
                                      child: Icon(
                                        LucideIcons.minus,
                                        size: context.ri(14),
                                        color: _buyNowQuantity > 1
                                            ? AppTheme.accent
                                            : AppTheme.mutedSteel,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: context.rPadding(horizontal: 12),
                                    child: Text(
                                      '$_buyNowQuantity',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: context.rsp(15),
                                        color: AppTheme.charcoalInk,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _buyNowQuantity < product.stockQuantity
                                        ? () => setState(() => _buyNowQuantity++)
                                        : null,
                                    child: Container(
                                      width: context.rw(28),
                                      height: context.rh(28),
                                      decoration: BoxDecoration(
                                        color: _buyNowQuantity < product.stockQuantity
                                            ? AppTheme.accent.withValues(alpha: 0.1)
                                            : AppTheme.warmMist,
                                        borderRadius: BorderRadius.circular(context.rr(6)),
                                        border: Border.all(color: AppTheme.whisperBorder),
                                      ),
                                      child: Icon(
                                        LucideIcons.plus,
                                        size: context.ri(14),
                                        color: _buyNowQuantity < product.stockQuantity
                                            ? AppTheme.accent
                                            : AppTheme.mutedSteel,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: context.rw(8)),
                                  Text(
                                    '${product.stockQuantity} available',
                                    style: TextStyle(
                                      fontSize: context.rsp(11),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (itemDeliveryFee > 0)
                              Padding(
                                padding: EdgeInsets.only(top: context.rh(2)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '  + Delivery Fee',
                                      style: TextStyle(
                                        fontSize: context.rsp(12),
                                        color: AppTheme.mutedSteel,
                                      ),
                                    ),
                                    Text(
                                      formatGhs(itemDeliveryFee),
                                      style: TextStyle(
                                        fontSize: context.rsp(12),
                                        color: AppTheme.mutedSteel,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // Cart mode: list items with quantity controls for stock > 1
                  ...cartItems.map((item) {
                    final itemDeliveryFee = _deliveryMode == 'delivery'
                        ? _getDeliveryFeeForProduct(item, _selectedDeliveryInstitution)
                        : 0.0;
                    final product = _productsMap[item.productId];
                    final maxStock = product?.stockQuantity ?? item.stock ?? 1;
                    return Padding(
                      padding: context.rPadding(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: const TextStyle(color: AppTheme.charcoalInk),
                                ),
                              ),
                              Text(
                                formatGhs(item.totalPrice),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (maxStock > 1) ...[
                            SizedBox(height: context.rh(8)),
                            Row(
                              children: [
                                Text(
                                  'Qty:',
                                  style: TextStyle(
                                    fontSize: context.rsp(13),
                                    color: AppTheme.mutedSteel,
                                  ),
                                ),
                                SizedBox(width: context.rw(8)),
                                GestureDetector(
                                  onTap: item.quantity > 1
                                      ? () => ref.read(cartProvider).updateQuantity(
                                          item.productId, item.quantity - 1)
                                      : null,
                                  child: Container(
                                    width: context.rw(28),
                                    height: context.rh(28),
                                    decoration: BoxDecoration(
                                      color: item.quantity > 1
                                          ? AppTheme.accent.withValues(alpha: 0.1)
                                          : AppTheme.warmMist,
                                      borderRadius: BorderRadius.circular(context.rr(6)),
                                      border: Border.all(color: AppTheme.whisperBorder),
                                    ),
                                    child: Icon(
                                      LucideIcons.minus,
                                      size: context.ri(14),
                                      color: item.quantity > 1
                                          ? AppTheme.accent
                                          : AppTheme.mutedSteel,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: context.rPadding(horizontal: 12),
                                  child: Text(
                                    '${item.quantity}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: context.rsp(15),
                                      color: AppTheme.charcoalInk,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: item.quantity < maxStock
                                      ? () => ref.read(cartProvider).updateQuantity(
                                          item.productId, item.quantity + 1)
                                      : null,
                                  child: Container(
                                    width: context.rw(28),
                                    height: context.rh(28),
                                    decoration: BoxDecoration(
                                      color: item.quantity < maxStock
                                          ? AppTheme.accent.withValues(alpha: 0.1)
                                          : AppTheme.warmMist,
                                      borderRadius: BorderRadius.circular(context.rr(6)),
                                      border: Border.all(color: AppTheme.whisperBorder),
                                    ),
                                    child: Icon(
                                      LucideIcons.plus,
                                      size: context.ri(14),
                                      color: item.quantity < maxStock
                                          ? AppTheme.accent
                                          : AppTheme.mutedSteel,
                                    ),
                                  ),
                                ),
                                SizedBox(width: context.rw(8)),
                                Text(
                                  '$maxStock available',
                                  style: TextStyle(
                                    fontSize: context.rsp(11),
                                    color: AppTheme.mutedSteel,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (itemDeliveryFee > 0)
                            Padding(
                              padding: EdgeInsets.only(top: context.rh(2)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '  + Delivery Fee',
                                    style: TextStyle(
                                      fontSize: context.rsp(12),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                  Text(
                                    'GH\u00a2 ${itemDeliveryFee.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: context.rsp(12),
                                      color: AppTheme.mutedSteel,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal',
                        style: TextStyle(color: AppTheme.mutedSteel)),
                    Text(
                      'GH\u00a2 ${subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Delivery',
                        style: TextStyle(color: AppTheme.mutedSteel)),
                    Text(
                      _deliveryMode == 'delivery' && _selectedDeliveryInstitution == null
                          ? 'Select campus'
                          : deliveryTotal > 0
                              ? 'GH\u00a2 ${deliveryTotal.toStringAsFixed(2)}'
                              : 'Free',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _deliveryMode == 'delivery' && _selectedDeliveryInstitution == null
                            ? AppTheme.destructive
                            : AppTheme.charcoalInk,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: context.rsp(16),
                          color: AppTheme.charcoalInk,
                        )),
                    Text(
                      'GH\u00a2 ${cartTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.rsp(18),
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: context.rh(16)),

          // Wallet Balance
          Container(
            padding: context.rAll(16),
            decoration: BoxDecoration(
              color: AppTheme.pureSurface,
              borderRadius: BorderRadius.circular(context.rr(16)),
              border: Border.all(color: AppTheme.whisperBorder),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.wallet, color: AppTheme.accent),
                SizedBox(width: context.rw(12)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet Balance',
                        style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(13))),
                    Text(
                      formatGhs(walletBalance),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasWalletBalance ? AppTheme.successMoss : AppTheme.destructive,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!hasWalletBalance && _paymentMethod == 'wallet')
                  ShadButton.ghost(
                    onPressed: () async {
                      await Navigator.of(context).pushNamed('/wallet');
                      if (context.mounted) {
                        unawaited(ref.read(walletProvider).loadWallet());
                      }
                    },
                    child: const Text('Fund Wallet'),
                  ),
              ],
            ),
          ),

          SizedBox(height: context.rh(16)),

          // Payment Method
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
                Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(12)),
                _PaymentOption(
                  title: 'Wallet Balance',
                  subtitle: hasWalletBalance
                      ? '${formatGhs(walletBalance)} available'
                      : 'Insufficient balance',
                  icon: LucideIcons.wallet,
                  isSelected: _paymentMethod == 'wallet',
                  enabled: hasWalletBalance,
                  onTap: hasWalletBalance
                      ? () => setState(() => _paymentMethod = 'wallet')
                      : null,
                ),
                SizedBox(height: context.rh(8)),
                _PaymentOption(
                  title: 'Paystack',
                  subtitle: 'Pay with card, mobile money, or bank',
                  icon: LucideIcons.creditCard,
                  isSelected: _paymentMethod == 'paystack',
                  onTap: () => setState(() => _paymentMethod = 'paystack'),
                ),
              ],
            ),
          ),

          SizedBox(height: context.rh(16)),

          // Delivery Mode
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
                Text(
                  'Delivery Method',
                  style: TextStyle(
                    fontSize: context.rsp(16),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(12)),
                _DeliveryOption(
                  title: 'Pickup',
                  subtitle: 'Arrange pickup with seller',
                  isSelected: _deliveryMode == 'pickup',
                  enabled: pickupEnabled,
                  onTap: () => setState(() {
                    _deliveryMode = 'pickup';
                    _selectedDeliveryInstitution = null;
                  }),
                ),
                SizedBox(height: context.rh(8)),
                _DeliveryOption(
                  title: 'Delivery',
                  subtitle: 'Seller delivers to your campus',
                  isSelected: _deliveryMode == 'delivery',
                  enabled: deliveryEnabled,
                  onTap: () => setState(() => _deliveryMode = 'delivery'),
                ),
                if (_deliveryMode == 'delivery') ...[
                  SizedBox(height: context.rh(16)),
                  Text(
                    'Delivery Location (Campus)',
                    style: TextStyle(
                      fontSize: context.rsp(14),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  SizedBox(height: context.rh(8)),
                  Builder(
                    builder: (context) {
                      final Set<String> sellerCampuses;
                      if (_isBuyNowMode) {
                        sellerCampuses = widget.buyNowProduct!.campuses.toSet();
                      } else {
                        sellerCampuses = cartItems
                            .map((item) => _productsMap[item.productId]?.campuses ?? <String>[])
                            .expand((c) => c)
                            .toSet();
                      }
                      final allowedInstitutions = _institutions
                          .where((inst) => sellerCampuses.any((c) =>
                              c.toLowerCase() == inst.name.toLowerCase() ||
                              c.toLowerCase() == inst.code.toLowerCase()))
                          .toList();
                      final displayInstitutions = allowedInstitutions.isNotEmpty
                          ? allowedInstitutions
                          : _institutions;

                      if (displayInstitutions.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return ShadSelect<String>(
                        key: ValueKey(_selectedDeliveryInstitution),
                        initialValue: _selectedDeliveryInstitution,
                        placeholder: const Text('Select your campus...'),
                        options: displayInstitutions.map((inst) {
                          return ShadOption(
                            value: inst.name,
                            child: Text('${inst.name} (${inst.code})'),
                          );
                        }).toList(),
                        selectedOptionBuilder: (context, value) {
                          final inst = displayInstitutions.firstWhere(
                            (i) => i.name == value,
                            orElse: () => Institution(id: '', code: value, name: value),
                          );
                          return Text('${inst.name} (${inst.code})');
                        },
                        onChanged: (val) {
                          setState(() {
                            _selectedDeliveryInstitution = val;
                          });
                        },
                      );
                    }
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: context.rh(100)),
        ],
      ),
      ),
    );
  }

  // Shows the full order details for confirmation; the actual placement
  // runs on Proceed through the same _placeOrder flow.
  void _openOrderConfirmation() {
    final List<CartItem> orderItems;
    final double subtotal;
    final double deliveryTotal;

    if (_isBuyNowMode) {
      final product = widget.buyNowProduct!;
      deliveryTotal = _deliveryMode == 'delivery'
          ? _getDeliveryFeeForBuyNow(_selectedDeliveryInstitution)
          : 0.0;
      subtotal = product.effectivePrice * _buyNowQuantity;
      orderItems = [
        CartItem(
          id: product.id,
          productId: product.id,
          title: product.title,
          thumbnail: product.effectiveThumbnail,
          price: product.effectivePrice,
          quantity: _buyNowQuantity,
          stock: product.stockQuantity,
          sellerId: product.sellerId,
          sellerName: product.sellerName,
          deliveryFee: deliveryTotal,
        ),
      ];
    } else {
      final cart = ref.read(cartProvider).cart;
      orderItems = cart.items;
      subtotal = cart.subtotalAmount;
      deliveryTotal = _deliveryMode == 'delivery'
          ? orderItems.fold<double>(
              0.0,
              (sum, item) => sum + _getDeliveryFeeForProduct(item, _selectedDeliveryInstitution),
            )
          : 0.0;
    }

    Navigator.of(context).push(
      AppTheme.fadeSlideRoute(
        OrderConfirmationScreen(
          items: orderItems,
          deliveryMode: _deliveryMode!,
          deliveryInstitution: _selectedDeliveryInstitution,
          paymentMethod: _paymentMethod,
          subtotal: subtotal,
          deliveryFee: deliveryTotal,
          onProceed: () async {
            await _placeOrder();
            return _orderPlaced;
          },
        ),
      ),
    );
  }

  Future<void> _placeOrder() async {
    final orderProv = ref.read(orderProvider);
    final walletProv = ref.read(walletProvider);
    final cartProv = ref.read(cartProvider);
    final authProv = ref.read(authProvider);

    // Block sellers from buying their own products
    final userId = authProv.user?.id;
    if (userId != null) {
      if (_isBuyNowMode && widget.buyNowProduct!.sellerId == userId) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('You cannot purchase your own product.')),
          );
        }
        return;
      }
      final ownItems = cartProv.cart.items.where((i) => i.sellerId == userId).toList();
      if (ownItems.isNotEmpty) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Remove your own products from the cart before checkout.')),
          );
        }
        return;
      }
    }

    // Require wallet lock authentication when paying with wallet
    if (_paymentMethod == 'wallet') {
      final authed = await WalletLockService.unlockIfNeeded(
        reason: 'Authenticate to confirm wallet payment',
      );
      if (!authed) return;
    }

    setState(() => _isProcessing = true);

    try {
      // Build items list and totals based on mode
      final List<CartItem> orderItems;
      final double orderTotal;

      if (_isBuyNowMode) {
        final product = widget.buyNowProduct!;
        final delFee = _deliveryMode == 'delivery'
            ? _getDeliveryFeeForBuyNow(_selectedDeliveryInstitution)
            : 0.0;
        orderItems = [
          CartItem(
            id: product.id,
            productId: product.id,
            title: product.title,
            thumbnail: product.effectiveThumbnail,
            price: product.effectivePrice,
            quantity: _buyNowQuantity,
            stock: product.stockQuantity,
            sellerId: product.sellerId,
            sellerName: product.sellerName,
            deliveryFee: delFee,
          ),
        ];
        orderTotal = (product.effectivePrice * _buyNowQuantity) + delFee;
      } else {
        orderItems = cartProv.cart.items;
        final deliveryTotal = _deliveryMode == 'delivery'
            ? orderItems.fold<double>(0.0, (sum, item) => sum + _getDeliveryFeeForProduct(item, _selectedDeliveryInstitution))
            : 0.0;
        orderTotal = cartProv.cart.subtotalAmount + deliveryTotal;
      }

      if (_paymentMethod == 'wallet') {
        final orderError = await orderProv.placeOrder(
          deliveryMode: _deliveryMode!,
          paymentMethod: 'wallet',
          cartItems: orderItems,
          deliveryInstitution: _selectedDeliveryInstitution,
        );

        if (orderError != null) {
          if (mounted) {
            ShadToaster.of(context).show(
              ShadToast(title: Text(orderError)),
            );
          }
          return;
        }

        final result = orderProv.lastOrderResult;
        final orderId = result?['order_id'] as String?;
        final items = (result?['items'] as List<dynamic>?) ?? [];

        if (orderId == null) {
          if (mounted) {
            ShadToaster.of(context).show(
              const ShadToast(title: Text('Failed to get order ID')),
            );
          }
          return;
        }

        final deductionError = await walletProv.deductAndCreateOrder(
          amount: orderTotal,
          orderId: orderId,
          description: 'Order payment',
        );

        if (deductionError != null) {
          if (mounted) {
            ShadToaster.of(context).show(
              ShadToast(title: Text(deductionError)),
            );
          }
          return;
        }

        if (!_isBuyNowMode) await cartProv.clearCart();

        // Send SMS with delivery codes
        if (authProv.user?.phoneNumber != null && items.isNotEmpty) {
          final codes = items.map((i) => i['delivery_code'] as String).join(', ');
          unawaited(SmsService.sendSms(
            to: authProv.user!.phoneNumber!,
            content: 'Your Instiy order #${orderId.substring(0, 8).toUpperCase()} has been placed! Delivery codes: $codes. Share with seller upon delivery.',
          ));
        }

        if (mounted) {
          _orderPlaced = true;  // prevent cart-empty guard from popping
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Order placed successfully!')),
          );
          // Pop back to explore root, then push orders screen on top
          Navigator.of(context).popUntil((route) => route.settings.name == '/explore' || route.isFirst);
          unawaited(Navigator.of(context).pushNamed('/orders'));
        }
      } else {
        // Initialize Paystack SDK
        final sdkOk = await PaystackService.initializeSDK();
        if (!sdkOk) {
          if (mounted) {
            ShadToaster.of(context).show(
              const ShadToast(title: Text('Failed to initialize Paystack SDK')),
            );
          }
          return;
        }

        // Fund wallet with orderTotal via Paystack
        final paystackResult = await PaystackService.fundWallet(orderTotal);
        if (!paystackResult.success) {
          if (mounted) {
            ShadToaster.of(context).show(
              ShadToast(title: Text(paystackResult.error ?? 'Paystack payment failed')),
            );
          }
          return;
        }

        final orderError = await orderProv.placeOrder(
          deliveryMode: _deliveryMode!,
          paymentMethod: 'wallet',
          cartItems: orderItems,
          paymentReference: paystackResult.reference,
          deliveryInstitution: _selectedDeliveryInstitution,
        );

        if (orderError != null) {
          if (mounted) {
            ShadToaster.of(context).show(
              ShadToast(title: Text(orderError)),
            );
          }
          return;
        }

        final result = orderProv.lastOrderResult;
        final orderId = result?['order_id'] as String?;
        final items = (result?['items'] as List<dynamic>?) ?? [];
        if (orderId == null) {
          if (mounted) {
            ShadToaster.of(context).show(
              const ShadToast(title: Text('Failed to retrieve order ID')),
            );
          }
          return;
        }

        // Deduct from wallet
        final deductionError = await walletProv.deductAndCreateOrder(
          amount: orderTotal,
          orderId: orderId,
          description: 'Order payment (via Paystack)',
        );

        if (deductionError != null) {
          if (mounted) {
            ShadToaster.of(context).show(
              ShadToast(title: Text(deductionError)),
            );
          }
          return;
        }

        if (!_isBuyNowMode) await cartProv.clearCart();

        // Send SMS with delivery codes
        if (authProv.user?.phoneNumber != null && items.isNotEmpty) {
          final codes = items.map((i) => i['delivery_code'] as String).join(', ');
          unawaited(SmsService.sendSms(
            to: authProv.user!.phoneNumber!,
            content: 'Your Instiy order #${orderId.substring(0, 8).toUpperCase()} has been placed! Delivery codes: $codes. Share with seller upon delivery.',
          ));
        }

        if (mounted) {
          _orderPlaced = true;  // prevent cart-empty guard from popping
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Order placed and paid successfully!')),
          );
          // Pop back to explore root, then push orders screen on top
          Navigator.of(context).popUntil((route) => route.settings.name == '/explore' || route.isFirst);
          unawaited(Navigator.of(context).pushNamed('/orders'));
        }
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Failed to place order: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

class _PaymentOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;

  const _PaymentOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? AppTheme.accent : AppTheme.mutedSteel;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.warmMist,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: isSelected ? effectiveColor : AppTheme.whisperBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? effectiveColor : AppTheme.mutedSteel),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? effectiveColor : AppTheme.charcoalInk,
                      )),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                ],
              ),
            ),
            if (isSelected)
              Icon(LucideIcons.check, color: AppTheme.accent, size: context.ri(20)),
          ],
        ),
      ),
    );
  }
}

class _DeliveryOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;

  const _DeliveryOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? AppTheme.accent : AppTheme.mutedSteel;
    final effectiveTextColor = enabled ? AppTheme.charcoalInk : AppTheme.mutedSteel;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: context.rAll(14),
        decoration: BoxDecoration(
          color: isSelected
              ? effectiveColor.withValues(alpha: 0.08)
              : AppTheme.warmMist,
          borderRadius: BorderRadius.circular(context.rr(12)),
          border: Border.all(
            color: isSelected ? effectiveColor : AppTheme.whisperBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? LucideIcons.check : LucideIcons.circle,
              color: isSelected ? effectiveColor : AppTheme.mutedSteel,
              size: context.ri(20),
            ),
            SizedBox(width: context.rw(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? effectiveColor : effectiveTextColor,
                      )),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: context.rsp(12), color: AppTheme.mutedSteel)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
