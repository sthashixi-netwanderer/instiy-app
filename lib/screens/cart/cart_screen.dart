import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/cart_provider.dart';
import '../../providers/providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../widgets/adaptive_nav.dart';
import '../../services/supabase_service.dart';
import '../../widgets/skeleton.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartProvider).loadCart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartProv = ref.watch(cartProvider);
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return ResponsiveLayout(
        type: ResponsiveLayoutType.general,
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Cart')),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shoppingCart, size: context.ri(64), color: AppTheme.mutedSteel),
              SizedBox(height: context.rh(16)),
              const Text('Sign in to view your cart',
                  style: TextStyle(color: AppTheme.mutedSteel)),
              SizedBox(height: context.rh(16)),
              ShadButton(
                onPressed: () => Navigator.of(context).pushNamed('/login'),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      );
    }

    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Cart')),
      bottomNavigationBar: cartProv.isLoading || cartProv.cart.items.isEmpty
          ? const AdaptiveNav(currentIndex: 1)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBottomBar(cartProv),
                const AdaptiveNav(currentIndex: 1),
              ],
            ),
      child: cartProv.isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 6))
          : cartProv.cart.items.isEmpty
              ? _buildEmptyCart()
              : _buildCartContent(cartProv),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.shoppingCart, size: context.ri(64), color: AppTheme.mutedSteel),
          SizedBox(height: context.rh(16)),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: context.rsp(18),
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoalInk,
            ),
          ),
          SizedBox(height: context.rh(8)),
          const Text(
            'Add products to continue to checkout.',
            style: TextStyle(color: AppTheme.mutedSteel),
          ),
          SizedBox(height: context.rh(24)),
          ShadButton(
            onPressed: () => Navigator.of(context).pushNamed('/explore'),
            child: const Text('Browse Products'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartContent(CartProvider provider) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(16),
        context.rw(16),
        context.rh(120), // space for checkout bar + bottom nav
      ),
      itemCount: provider.cart.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = provider.cart.items[index];
        return _CartItemCard(
          item: item,
          onIncrement: () => provider.updateQuantity(item.id, item.quantity + 1),
          onDecrement: () => provider.updateQuantity(item.id, item.quantity - 1),
          onRemove: () => provider.removeItem(item.id),
        );
      },
    );
  }

  Widget _buildBottomBar(CartProvider provider) {
    return Container(
      padding: context.rAll(20),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        border: Border(top: BorderSide(color: AppTheme.whisperBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: TextStyle(color: AppTheme.mutedSteel, fontSize: context.rsp(13))),
                Text(
                  'GH\u00a2 ${provider.cart.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: context.rsp(22),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: context.rw(160),
            height: context.rh(50),
            child: ShadButton(
              onPressed: () => _checkSellersAndCheckout(context, provider),
              child: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkSellersAndCheckout(BuildContext context, CartProvider provider) async {
    final sellerIds = provider.cart.items
        .map((item) => item.sellerId)
        .whereType<String>()
        .toSet()
        .toList();

    if (sellerIds.isEmpty) {
      await Navigator.of(context).pushNamed('/checkout');
      return;
    }

    try {
      // Show loading indicator (don't await — it blocks until dismissed)
      unawaited(showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      ));

      final response = await SupabaseService.client
          .from('users')
          .select('id, full_name, is_verified')
          .inFilter('id', sellerIds);

      // Dismiss loading dialog
      if (context.mounted) Navigator.of(context).pop();

      final unverifiedSellers = <String>[];
      for (final row in response) {
        final isVerified = row['is_verified'] as bool? ?? false;
        if (!isVerified) {
          unverifiedSellers.add(row['full_name'] as String? ?? 'Unknown Seller');
        }
      }

      if (unverifiedSellers.isNotEmpty) {
        if (!context.mounted) return;
        final proceed = await AppTheme.showGlassDialog<bool>(
          context: context,
          title: const Text('Unverified Seller Warning'),
          description: Text(
            'The following seller(s) are not verified:\n'
            '• ${unverifiedSellers.join("\n• ")}\n\n'
            'Please note that Instiy will not be responsible for any misunderstanding or issues arising from transactions with unverified sellers.',
          ),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Proceed Anyway'),
            ),
          ],
        );

        if (proceed == true) {
          if (context.mounted) {
            await Navigator.of(context).pushNamed('/checkout');
          }
        }
      } else {
        if (context.mounted) {
          await Navigator.of(context).pushNamed('/checkout');
        }
      }
    } catch (e) {
      if (context.mounted) {
        // Fallback
        await Navigator.of(context).pushNamed('/checkout');
      }
    }
  }
}

class _CartItemCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.rPadding(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(context.rr(12)),
            child: SizedBox(
              width: context.rw(80),
              height: context.rh(80),
              child: item.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: item.thumbnail,
                      fit: BoxFit.cover,
                      memCacheWidth: 80,
                      placeholder: (_, _) => Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.warmMist,
                        child: const Icon(LucideIcons.image, color: AppTheme.mutedSteel),
                      ),
                    )
                  : Container(
                      color: AppTheme.warmMist,
                      child: const Icon(LucideIcons.image, color: AppTheme.mutedSteel),
                    ),
            ),
          ),
          SizedBox(width: context.rw(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(4)),
                Text(
                  'GH\u00a2 ${item.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              ShadIconButton.ghost(
                icon: Icon(LucideIcons.minus, size: context.ri(22), color: AppTheme.mutedSteel),
                onPressed: item.quantity <= 1 ? onRemove : onDecrement,
              ),
              Text(
                '${item.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              ShadIconButton.ghost(
                icon: Icon(LucideIcons.plus, size: context.ri(22), color: AppTheme.accent),
                onPressed: onIncrement,
              ),
            ],
          ),
          ShadIconButton.ghost(
            icon: Icon(LucideIcons.trash2, size: context.ri(20), color: AppTheme.destructive),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
