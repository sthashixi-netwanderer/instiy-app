import 'supabase_service.dart';
import '../models/business_profile_model.dart';
import '../models/seller_review_model.dart';
import '../models/product_model.dart';

class BusinessProfileService {
  static Future<BusinessProfile?> getProfile(String sellerId) async {
    final response = await SupabaseService.table('business_profiles')
        .select('*, users!seller_id(university, avatar_url)')
        .eq('seller_id', sellerId)
        .maybeSingle();

    if (response == null) return null;
    return BusinessProfile.fromJson(response);
  }

  static Future<BusinessProfile> upsertProfile({
    required String sellerId,
    String? bannerUrl,
    String? businessName,
    String? description,
    String? locationUrl,
    String? digitalAddress,
    bool? qrCodePublic,
    List<StorePhoneNumber>? phoneNumbers,
  }) async {
    final data = <String, dynamic>{
      'seller_id': sellerId,
    };

    if (bannerUrl != null) data['banner_url'] = bannerUrl;
    if (businessName != null) data['business_name'] = businessName;
    if (description != null) data['description'] = description;
    if (locationUrl != null) data['location_url'] = locationUrl;
    if (digitalAddress != null) data['digital_address'] = digitalAddress;
    if (qrCodePublic != null) data['qr_code_public'] = qrCodePublic;
    if (phoneNumbers != null) {
      data['phone_numbers'] = phoneNumbers.map((p) => p.toJson()).toList();
    }

    final response = await SupabaseService.table('business_profiles')
        .upsert(data, onConflict: 'seller_id')
        .select()
        .single();

    return BusinessProfile.fromJson(response);
  }

  static Future<void> deleteBanner(String sellerId) async {
    await SupabaseService.table('business_profiles')
        .update({'banner_url': null})
        .eq('seller_id', sellerId);
  }

  static Future<StoreStats> getStoreStats(String sellerId) async {
    final response = await SupabaseService.client.rpc(
      'get_seller_store_stats',
      params: {'p_seller_id': sellerId},
    );

    if (response is List && response.isNotEmpty) {
      return StoreStats.fromJson(response.first as Map<String, dynamic>);
    }
    return StoreStats();
  }

  static Future<List<ProductReview>> getStoreReviews({
    required String sellerId,
    int offset = 0,
    int limit = 20,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_seller_store_reviews',
      params: {
        'p_seller_id': sellerId,
        'p_offset': offset,
        'p_limit': limit,
      },
    );

    return (response as List)
        .map((json) => ProductReview.fromRpcJson(json as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Product>> getStoreProducts(String sellerId) async {
    final response = await SupabaseService.table('products')
        .select('''
          *,
          seller:users!seller_id(full_name, avatar_url, is_verified, university, business_profiles(business_name))
        ''')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> getSellerVerificationStatus(String sellerId) async {
    final response = await SupabaseService.table('users')
        .select('is_verified')
        .eq('id', sellerId)
        .maybeSingle();

    return response?['is_verified'] == true;
  }

  static Future<bool> isFollowing(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await SupabaseService.client.rpc(
      'is_following_seller',
      params: {'p_seller_id': sellerId},
    );

    return response == true;
  }

  static Future<void> follow(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    await SupabaseService.table('seller_follows').insert({
      'follower_id': userId,
      'seller_id': sellerId,
    });
  }

  static Future<void> unfollow(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    await SupabaseService.table('seller_follows')
        .delete()
        .eq('follower_id', userId)
        .eq('seller_id', sellerId);
  }
}
