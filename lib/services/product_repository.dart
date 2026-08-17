import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:instiy/models/product_model.dart';
import 'package:instiy/services/hive_cache_service.dart';
import 'package:instiy/services/supabase_service.dart';

class ProductRepository {
  static const String _cacheKey = 'all_products';

  /// Returns a stream of products. 
  /// It immediately emits cached products (if any), then fetches fresh data 
  /// from Supabase in the background, updates the cache, and emits the fresh data.
  Stream<List<Product>> watchProducts() async* {
    // 1. Yield local cache immediately for zero-loading shimmer
    final cachedData = HiveCacheService.productsBox.get(_cacheKey);
    if (cachedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedData);
        final products = decoded.map((e) => Product.fromJson(e)).toList();
        yield products;
      } catch (e) {
        debugPrint('Error parsing cached products: $e');
        // If cache is corrupted, we don't yield it, just wait for network
      }
    } else {
      // Yield an empty list if there's no cache, or you could opt to not yield 
      // anything so the UI shows a loading state on first ever launch.
      yield [];
    }

    // 2. Fetch fresh data from Supabase in the background
    try {
      final response = await SupabaseService.client
          .from('products')
          .select('*, seller:seller_id(*, business_profiles(*)), category:category_id(*)')
          .eq('status', 'available')
          .order('created_at', ascending: false)
          .limit(50); // Limit to 50 for the home feed catalog cache

      final freshProducts = (response as List<dynamic>)
          .map((e) => Product.fromJson(e))
          .toList();

      // 3. Upsert the fresh data to local cache
      final jsonList = freshProducts.map((p) => p.toJson()).toList();
      await HiveCacheService.productsBox.put(_cacheKey, jsonEncode(jsonList));

      // 4. Emit the updated results to seamlessly update the UI
      yield freshProducts;
    } catch (e) {
      debugPrint('Error fetching products from network: $e');
      // If network fails, we've already yielded the cache. The UI stays intact.
      // We don't throw to prevent breaking the stream listener if they rely on it.
    }
  }
}
