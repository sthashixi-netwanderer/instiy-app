import 'dart:math';
import 'supabase_service.dart';

class PurchasePermissionService {
  static String _generateRandomAlphanumeric(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Generates a unique 6 alphanumeric code and creates a pending purchase permission.
  static Future<String> generatePermissionCode({
    required String productId,
    required String sellerId,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) throw Exception('User not authenticated');

    for (int retry = 0; retry < 5; retry++) {
      final code = _generateRandomAlphanumeric(6);
      try {
        await supabase.from('purchase_permissions').insert({
          'code': code,
          'customer_id': uid,
          'product_id': productId,
          'seller_id': sellerId,
          'status': 'pending',
        });
        return code;
      } catch (e) {
        // If unique constraint violation, loop and try again.
        if (retry == 4) rethrow;
      }
    }
    throw Exception('Failed to generate a unique permission code.');
  }

  /// Looks up a permission by its 6-character code.
  /// Returns customer details and product details as well.
  static Future<Map<String, dynamic>?> getPermissionByCode(String code) async {
    final supabase = SupabaseService.instance;
    try {
      final response = await supabase
          .from('purchase_permissions')
          .select('''
            *,
            customer:users!purchase_permissions_customer_id_fkey(id, email, full_name, avatar_url, university),
            product:products!purchase_permissions_product_id_fkey(id, title, price, image_urls, thumbnail_url)
          ''')
          .eq('code', code.toUpperCase().trim())
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Grants permission for a customer to buy the product. Sets status to 'granted' and expires_at to +24 hours.
  static Future<void> grantPermission(String permissionId) async {
    final supabase = SupabaseService.instance;
    final expiresAt = DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String();
    await supabase.from('purchase_permissions').update({
      'status': 'granted',
      'expires_at': expiresAt,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', permissionId);
  }

  /// Fetches permission history for a seller, ordered by most recent.
  static Future<List<Map<String, dynamic>>> getPermissionHistory({
    required String sellerId,
    int offset = 0,
    int limit = 20,
  }) async {
    final supabase = SupabaseService.instance;
    try {
      final response = await supabase
          .from('purchase_permissions')
          .select('''
            *,
            customer:users!purchase_permissions_customer_id_fkey(id, full_name, avatar_url, university),
            product:products!purchase_permissions_product_id_fkey(id, title, price, image_urls, thumbnail_url)
          ''')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Checks if the current authenticated customer has an active (granted) permission for the specified product.
  static Future<bool> hasActivePermission({
    required String productId,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return false;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await supabase
          .from('purchase_permissions')
          .select('id')
          .eq('customer_id', uid)
          .eq('product_id', productId)
          .eq('status', 'granted')
          .gt('expires_at', now)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }
}
