import 'dart:isolate';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import '../models/category_model.dart';
import 'supabase_service.dart';
import 'business_profile_service.dart';

// Top-level function for isolate — parses raw JSON list into Products
List<Product> _parseProductList(List<dynamic> rawList) {
  return rawList
      .where((json) {
        final category = json['category'] as Map<String, dynamic>?;
        if (category != null && category['type'] == 'service') {
          return false;
        }
        return true;
      })
      .map((json) {
        final seller = json['seller'] as Map<String, dynamic>?;
        final category = json['category'] as Map<String, dynamic>?;

        return Product.fromJson({
          ...json,
          'seller_name': seller?['full_name'],
          'seller_avatar': seller?['avatar_url'],
          'seller_email': seller?['email'],
          'seller_phone': seller?['phone_number'],
          'is_seller_verified': seller?['is_verified'] ?? false,
          'category_name': category?['name'],
        });
      })
      .toList();
}

class ProductService {
  // ─── Product Views ──────────────────────────────────────────────────────

  /// Cached public IP for anonymous view dedup (fetched once per session).
  static String? _cachedPublicIp;

  static Future<String?> _getPublicIp() async {
    if (_cachedPublicIp != null) return _cachedPublicIp;
    try {
      final response = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
        _cachedPublicIp = response.body.trim();
      }
    } catch (_) {}
    return _cachedPublicIp;
  }

  /// Records a view for [productId] (deduped per user, or per IP when not
  /// signed in) and returns the product's total view count.
  static Future<int> recordProductView(String productId) async {
    try {
      final isAuthed = SupabaseService.client.auth.currentUser != null;
      final viewerIp = isAuthed ? null : await _getPublicIp();
      final response = await SupabaseService.client.rpc(
        'record_product_view',
        params: {'p_product_id': productId, 'p_viewer_ip': viewerIp},
      );
      return (response as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches view counts for a batch of product ids (seller lists, grids).
  static Future<Map<String, int>> getViewCounts(List<String> productIds) async {
    if (productIds.isEmpty) return {};
    try {
      final response = await SupabaseService.client.rpc(
        'get_product_view_counts',
        params: {'p_product_ids': productIds},
      );
      final counts = <String, int>{};
      for (final row in (response as List)) {
        final map = row as Map<String, dynamic>;
        counts[map['product_id'] as String] =
            (map['view_count'] as num?)?.toInt() ?? 0;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }

  // Get all products with optional filters
  static Future<List<Product>> getProducts({
    String? categoryId,
    String? searchQuery,
    ProductStatus? status,
    String? sellerId,
    List<String>? conditions,
    double? minPrice,
    double? maxPrice,
    List<String>? campuses,
    String sortBy = 'newest',
    int limit = 20,
    int offset = 0,
  }) async {
    var query = SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''');

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    if (sellerId != null) {
      query = query.eq('seller_id', sellerId);
      if (status != null) {
        query = query.eq('status', status.name);
      }
    } else {
      if (status != null) {
        query = query.eq('status', status.name);
      } else {
        query = query.eq('status', 'available');
      }
      query = query.gt('stock_quantity', 0);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'title.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
      );
    }

    if (conditions != null && conditions.isNotEmpty) {
      query = query.inFilter('condition', conditions);
    }

    if (minPrice != null) {
      query = query.gte('price', minPrice);
    }

    if (maxPrice != null) {
      query = query.lte('price', maxPrice);
    }

    if (campuses != null && campuses.isNotEmpty) {
      // Products with no campus restriction ("All Institutions" listings)
      // match every institution filter.
      final orConditions =
          'campus.is.null,${campuses.map((c) => 'campus.ilike.%$c%').join(',')}';
      query = query.or(orConditions);
    }

    // Apply sorting
    String sortColumn = 'created_at';
    bool ascending = false;
    if (sortBy == 'price_asc') {
      sortColumn = 'price';
      ascending = true;
    } else if (sortBy == 'price_desc') {
      sortColumn = 'price';
      ascending = false;
    }

    final response = await query
        .order(sortColumn, ascending: ascending)
        .range(offset, offset + limit - 1);

    final products = await Isolate.run(() => _parseProductList(response as List));

    // Fetch review aggregates for all products
    if (products.isNotEmpty) {
      final productIds = products.map((p) => p.id).toList();
      final reviewsResponse = await SupabaseService.table('product_reviews')
          .select('product_id, rating')
          .inFilter('product_id', productIds)
          .not('rating', 'is', null);

      final reviews = reviewsResponse as List;
      final Map<String, List<num>> ratingsByProduct = {};
      for (final review in reviews) {
        final productId = review['product_id'] as String;
        final rating = review['rating'] as num?;
        if (rating != null) {
          ratingsByProduct.putIfAbsent(productId, () => []).add(rating);
        }
      }

      return products.map((product) {
        final ratings = ratingsByProduct[product.id];
        if (ratings != null && ratings.isNotEmpty) {
          final avg = ratings.reduce((a, b) => a + b) / ratings.length;
          return product.copyWith(
            averageRating: avg,
            reviewCount: ratings.length,
          );
        }
        return product.copyWith(averageRating: 0, reviewCount: 0);
      }).toList();
    }

    return products;
  }

  // Get single product
  static Future<Product> getProduct(String productId) async {
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .eq('id', productId)
        .single();

    final seller = response['seller'] as Map<String, dynamic>?;
    final category = response['category'] as Map<String, dynamic>?;

    // Load per-institution delivery fees
    final feeRows = await SupabaseService.table('product_institution_deliveries')
        .select('institution_name, delivery_fee')
        .eq('product_id', productId);

    return Product.fromJson({
      ...response,
      'seller_name': seller?['full_name'],
      'seller_avatar': seller?['avatar_url'],
      'is_seller_verified': seller?['is_verified'] ?? false,
      'seller_email': seller?['email'],
      'seller_phone': seller?['phone_number'],
      'category_name': category?['name'],
      'institution_delivery_fees': (feeRows as List?)?.toList() ?? [],
    });
  }

  // Get single product by slug (for deep links)
  static Future<Product?> getProductBySlug(String slugId) async {
    try {
      final response = await SupabaseService.table('products')
          .select('''
            *,
            seller:users!seller_id(full_name, avatar_url, is_verified, business_profiles(business_name)),
            category:categories(name, type)
          ''')
          .eq('slug', slugId)
          .maybeSingle();

      if (response == null) return null;

      final seller = response['seller'] as Map<String, dynamic>?;
      final category = response['category'] as Map<String, dynamic>?;

      final feeRows = await SupabaseService.table('product_institution_deliveries')
          .select('institution_name, delivery_fee')
          .eq('product_id', response['id']);

      return Product.fromJson({
        ...response,
        'seller_name': seller?['full_name'],
        'seller_avatar': seller?['avatar_url'],
        'is_seller_verified': seller?['is_verified'] ?? false,
        'seller_email': seller?['email'],
        'seller_phone': seller?['phone_number'],
        'category_name': category?['name'],
        'institution_delivery_fees': (feeRows as List?)?.toList() ?? [],
      });
    } catch (e) {
      return null;
    }
  }

  // Get single product with review data
  static Future<Product> getProductWithReviews(String productId) async {
    final product = await getProduct(productId);

    final reviewsResponse = await SupabaseService.table('product_reviews')
        .select('rating')
        .eq('product_id', productId)
        .not('rating', 'is', null);

    final reviews = reviewsResponse as List;
    if (reviews.isNotEmpty) {
      final ratings = reviews.map((r) => r['rating'] as num).toList();
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      return product.copyWith(
        averageRating: avg,
        reviewCount: ratings.length,
      );
    }

    return product.copyWith(averageRating: 0, reviewCount: 0);
  }

  // Create new product
  static Future<Product> createProduct({
    required String title,
    required String description,
    required double price,
    String? categoryId,
    required List<String> imageUrls,
    List<String> videoUrls = const [],
    required ProductCondition condition,
    List<String>? campuses,
    List<Map<String, String>>? specifications,
    int stockQuantity = 1,
    String deliveryOption = 'pickup',
    double deliveryFee = 0.0,
    double discountPercent = 0,
    String? discountStartDate,
    String? discountEndDate,
    String? thumbnailUrl,
    Map<String, double>? institutionDeliveryFees,
    bool showOnClips = false,
    String? clipVideoUrl,
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Business profile is required to list products
    final profile = await BusinessProfileService.getProfile(userId);
    if (profile == null) {
      throw Exception('Business profile required. Please set up your store profile first.');
    }

    final productData = {
      'seller_id': userId,
      'title': title,
      'description': description,
      'price': price,
      'category_id': categoryId,
      'image_urls': imageUrls,
      'video_urls': videoUrls,
      'condition': condition.name,
      'status': 'available',
      'campus': campuses?.join(', '),
      'specifications': specifications ?? [],
      'stock_quantity': stockQuantity,
      'delivery_option': deliveryOption,
      'delivery_fee': deliveryFee,
      'discount_percent': discountPercent,
      'discount_start_date': discountStartDate,
      'discount_end_date': discountEndDate,
      'thumbnail_url': thumbnailUrl,
      'show_on_clips': showOnClips,
      'clip_video_url': clipVideoUrl,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await SupabaseService.table('products')
        .insert(productData)
        .select()
        .single();

    final productId = response['id'] as String;

    // Save per-institution delivery fees
    if (institutionDeliveryFees != null && institutionDeliveryFees.isNotEmpty) {
      await _saveInstitutionFees(productId, institutionDeliveryFees);
    }

    return Product.fromJson({
      ...response,
      'institution_delivery_fees': institutionDeliveryFees?.entries
          .map((e) => {'institution_name': e.key, 'delivery_fee': e.value})
          .toList() ?? [],
    });
  }

  // Update product
  static Future<Product> updateProduct({
    required String productId,
    String? title,
    String? description,
    double? price,
    String? categoryId,
    List<String>? imageUrls,
    List<String>? videoUrls,
    ProductCondition? condition,
    ProductStatus? status,
    List<String>? campuses,
    List<Map<String, String>>? specifications,
    int? stockQuantity,
    String? deliveryOption,
    double? deliveryFee,
    double? discountPercent,
    String? discountStartDate,
    String? discountEndDate,
    String? thumbnailUrl,
    Map<String, double>? institutionDeliveryFees,
    bool? showOnClips,
    String? clipVideoUrl,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (title != null) {
      updates['title'] = title;
      // If title is not null, this is a full product edit form submission.
      // We explicitly set category_id and discount dates (which can be cleared to null).
      updates['category_id'] = categoryId;
      updates['discount_start_date'] = discountStartDate;
      updates['discount_end_date'] = discountEndDate;
    } else {
      if (categoryId != null) updates['category_id'] = categoryId;
      if (discountStartDate != null) updates['discount_start_date'] = discountStartDate;
      if (discountEndDate != null) updates['discount_end_date'] = discountEndDate;
    }
    if (description != null) updates['description'] = description;
    if (price != null) updates['price'] = price;
    if (imageUrls != null) updates['image_urls'] = imageUrls;
    if (videoUrls != null) updates['video_urls'] = videoUrls;
    if (condition != null) updates['condition'] = condition.name;
    if (status != null) updates['status'] = status.name;
    if (campuses != null) updates['campus'] = campuses.join(', ');
    if (specifications != null) updates['specifications'] = specifications;
    if (stockQuantity != null) updates['stock_quantity'] = stockQuantity;
    if (deliveryOption != null) updates['delivery_option'] = deliveryOption;
    if (deliveryFee != null) updates['delivery_fee'] = deliveryFee;
    if (discountPercent != null) updates['discount_percent'] = discountPercent;
    // thumbnailUrl is always included (even if null) so it can be explicitly cleared
    updates['thumbnail_url'] = thumbnailUrl;

    if (showOnClips != null) updates['show_on_clips'] = showOnClips;
    if (clipVideoUrl != null) updates['clip_video_url'] = clipVideoUrl;

    final response = await SupabaseService.table('products')
        .update(updates)
        .eq('id', productId)
        .select()
        .single();

    // Save per-institution delivery fees
    if (institutionDeliveryFees != null) {
      await _saveInstitutionFees(productId, institutionDeliveryFees);
    }

    return Product.fromJson({
      ...response,
      'institution_delivery_fees': institutionDeliveryFees?.entries
          .map((e) => {'institution_name': e.key, 'delivery_fee': e.value})
          .toList() ?? [],
    });
  }

  // Save per-institution delivery fees (replaces all existing entries)
  static Future<void> _saveInstitutionFees(String productId, Map<String, double> fees) async {
    // Delete existing fees
    await SupabaseService.table('product_institution_deliveries')
        .delete()
        .eq('product_id', productId);

    // Insert new fees
    if (fees.isNotEmpty) {
      await SupabaseService.table('product_institution_deliveries').insert(
        fees.entries.map((e) => {
          'product_id': productId,
          'institution_name': e.key,
          'delivery_fee': e.value,
        }).toList(),
      );
    }
  }

  // Delete product — only if no pending deliveries
  static Future<String?> deleteProduct(String productId) async {
    // Check for pending order items
    final pendingItems = await SupabaseService.table('order_items')
        .select('id')
        .eq('product_id', productId)
        .not('status', 'in', '(delivered,cancelled)');

    if ((pendingItems as List).isNotEmpty) {
      return 'Cannot delete: this product has pending deliveries. Complete or cancel them first.';
    }

    await SupabaseService.table('products')
        .delete()
        .eq('id', productId);
    return null; // success
  }

  // Get categories
  static Future<List<Category>> getCategories({String? type}) async {
    var query = SupabaseService.table('categories')
        .select();

    if (type != null) {
      query = query.eq('type', type);
    }

    final response = await query.order('name');

    return (response as List)
        .map((json) => Category.fromJson(json))
        .toList();
  }

  static Future<List<Product>> getFeaturedProducts({int limit = 10}) async {
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .eq('status', 'available')
        .eq('is_featured', true)
        .order('created_at', ascending: false)
        .limit(limit);

    return Isolate.run(() => _parseProductList(response as List));
  }

  // Get trending products (newest available, proxy for popularity)
  static Future<List<Product>> getTrendingProducts({int limit = 10}) async {
    try {
      final response = await SupabaseService.client
          .rpc('get_trending_products', params: {'p_limit': limit})
          .select();

      if ((response as List).isNotEmpty) {
        final ids = response.map((p) => p['id'] as String).toList();
        // Awaited so a fetch failure falls through to the fallback below.
        return await _fetchProductDetails(ids);
      }
    } catch (_) {}

    // Fallback: newest available products
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .eq('status', 'available')
        .order('created_at', ascending: false)
        .limit(limit);

    return Isolate.run(() => _parseProductList(response as List));
  }

  // Get best seller products (hybrid scoring: sales velocity + margin + stock)
  static Future<List<Product>> getBestSellers({String? categoryId, int limit = 10}) async {
    try {
      final response = await SupabaseService.client
          .rpc('get_best_seller_products', params: {
            'p_limit': limit,
            'p_category_id': categoryId,
          })
          .select();

      if ((response as List).isNotEmpty) {
        final ids = response.map((p) => p['id'] as String).toList();
        // Awaited so a fetch failure falls through to the fallback below.
        return await _fetchProductDetails(ids);
      }
    } catch (_) {}

    // Fallback: newest available products
    var query = SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .eq('status', 'available');

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final response = await query.order('created_at', ascending: false).limit(limit);

    return Isolate.run(() => _parseProductList(response as List));
  }

  // Helper: fetch full product details by IDs (preserving order)
  static Future<List<Product>> _fetchProductDetails(List<String> ids) async {
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .inFilter('id', ids);

    return Isolate.run(() {
      final products = _parseProductList(response as List);
      // Preserve the original ordering from the RPC
      final idOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      products.sort((a, b) => (idOrder[a.id] ?? 999).compareTo(idOrder[b.id] ?? 999));
      return products;
    });
  }

  // Get user's listings
  static Future<List<Product>> getUserListings(String userId) async {
    return getProducts(sellerId: userId);
  }

  // Mark product as sold
  static Future<void> markAsSold(String productId) async {
    await SupabaseService.table('products')
        .update({
          'status': 'sold',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', productId);
  }

  // Favorites
  static Future<List<String>> getFavoriteIds() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await SupabaseService.table('favorites')
        .select('product_id')
        .eq('user_id', userId);

    return (response as List)
        .map((row) => row['product_id'] as String)
        .toList();
  }

  static Future<bool> isFavorited(String productId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await SupabaseService.table('favorites')
        .select('product_id')
        .eq('user_id', userId)
        .eq('product_id', productId)
        .maybeSingle();

    return response != null;
  }

  static Future<void> addFavorite(String productId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await SupabaseService.table('favorites').insert({
      'user_id': userId,
      'product_id': productId,
    });
  }

  static Future<void> removeFavorite(String productId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await SupabaseService.table('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('product_id', productId);
  }

  // Get related products (same category, excluding current product)
  static Future<List<Product>> getRelatedProducts(String productId, {int limit = 10}) async {
    // First fetch the current product to get its category
    final current = await SupabaseService.table('products')
        .select('category_id')
        .eq('id', productId)
        .maybeSingle();

    if (current == null) return [];

    final categoryId = current['category_id'] as String?;
    if (categoryId == null) return [];

    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name, type)
        ''')
        .eq('category_id', categoryId)
        .eq('status', 'available')
        .gt('stock_quantity', 0)
        .neq('id', productId)
        .order('created_at', ascending: false)
        .limit(limit);

    return Isolate.run(() => _parseProductList(response as List));
  }

  // Get products with videos for Clips/TikTok feed
  static Future<List<Product>> getClipsProducts({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, email, phone_number, is_verified, business_profiles(business_name)),
          category:categories(name)
        ''')
        .eq('status', 'available')
        .gt('stock_quantity', 0)
        .eq('show_on_clips', true)
        .not('video_urls', 'eq', '{}')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final products = await Isolate.run(() => _parseProductList(response as List));

    // Fetch review aggregates for all products
    if (products.isNotEmpty) {
      final productIds = products.map((p) => p.id).toList();
      try {
        final reviewsResponse = await SupabaseService.table('product_reviews')
            .select('product_id, rating')
            .inFilter('product_id', productIds)
            .not('rating', 'is', null);

        final reviews = reviewsResponse as List;
        final Map<String, List<num>> ratingsByProduct = {};
        for (final review in reviews) {
          final productId = review['product_id'] as String;
          final rating = review['rating'] as num?;
          if (rating != null) {
            ratingsByProduct.putIfAbsent(productId, () => []).add(rating);
          }
        }

        for (var i = 0; i < products.length; i++) {
          final p = products[i];
          final productRatings = ratingsByProduct[p.id];
          if (productRatings != null && productRatings.isNotEmpty) {
            final avg = productRatings.reduce((a, b) => a + b) / productRatings.length;
            products[i] = p.copyWith(
              averageRating: avg,
              reviewCount: productRatings.length,
            );
          } else {
            products[i] = p.copyWith(averageRating: 0.0, reviewCount: 0);
          }
        }
      } catch (_) {
        // Fallback if reviews table fails
      }
    }
    return products;
  }
}
