import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instiy/providers/home_products_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:instiy/utils/formatters.dart';

/// A demonstration of the "Spotify Free Account" cache-first pattern.
/// The `homeProductsControllerProvider` immediately emits cached products from Hive
/// to avoid loading spinners, while silently fetching from Supabase in the background.
class CacheFirstDemoWidget extends ConsumerWidget {
  const CacheFirstDemoWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(homeProductsControllerProvider);

    return productsState.when(
      // We skip loading if we have previous data. It transitions seamlessly.
      skipLoadingOnReload: true,
      data: (products) {
        if (products.isEmpty) {
          return const Center(
            child: Text('No products found.'),
          );
        }

        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              leading: _buildThumbnail(product.effectiveThumbnail),
              title: Text(product.title),
              subtitle: Text('${formatCurrency(product.effectivePrice)}'),
              onTap: () {
                // Navigate to detail
              },
            );
          },
        );
      },
      error: (err, stack) {
        // Since we use the cache first, error states usually only occur if BOTH 
        // the cache is empty AND the network fails. Otherwise, it retains the 
        // cached data and just logs the background network failure silently.
        return Center(
          child: Text('Error loading products: $err'),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildThumbnail(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 50,
        height: 50,
        color: Colors.grey[200],
        child: const Icon(Icons.image),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => const Icon(Icons.error),
    );
  }
}
