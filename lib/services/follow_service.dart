import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import 'email_service.dart';

class FollowService {
  /// Check if the current user is following [sellerId]
  static Future<bool> isFollowing(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await SupabaseService.client
        .from('seller_follows')
        .select('id')
        .eq('follower_id', userId)
        .eq('seller_id', sellerId)
        .maybeSingle();

    return response != null;
  }

  /// Get follower count for a seller
  static Future<int> getFollowerCount(String sellerId) async {
    final response = await SupabaseService.client
        .from('seller_follows')
        .select('id')
        .eq('seller_id', sellerId);
    return (response as List).length;
  }

  /// Get following count for a user (how many sellers they follow)
  static Future<int> getFollowingCount(String userId) async {
    final response = await SupabaseService.client
        .from('seller_follows')
        .select('id')
        .eq('follower_id', userId);
    return (response as List).length;
  }

  /// Get list of users following a seller (followers)
  static Future<List<Map<String, dynamic>>> getFollowersList(String sellerId) async {
    final response = await SupabaseService.table('seller_follows')
        .select('follower_id, users!follower_id(id, full_name, avatar_url, university, is_verified)')
        .eq('seller_id', sellerId);

    return (response as List).map((row) {
      final user = row['users'] as Map<String, dynamic>?;
      return {
        'id': user?['id'] as String? ?? row['follower_id'],
        'name': user?['full_name'] as String? ?? 'User',
        'avatar_url': user?['avatar_url'] as String?,
        'university': user?['university'] as String?,
        'is_verified': user?['is_verified'] as bool? ?? false,
      };
    }).toList();
  }

  /// Get list of sellers a user is following
  static Future<List<Map<String, dynamic>>> getFollowingList(String userId) async {
    final response = await SupabaseService.table('seller_follows')
        .select('seller_id, users!seller_id(id, full_name, avatar_url, university, is_verified)')
        .eq('follower_id', userId);

    return (response as List).map((row) {
      final user = row['users'] as Map<String, dynamic>?;
      return {
        'id': user?['id'] as String? ?? row['seller_id'],
        'name': user?['full_name'] as String? ?? 'User',
        'avatar_url': user?['avatar_url'] as String?,
        'university': user?['university'] as String?,
        'is_verified': user?['is_verified'] as bool? ?? false,
      };
    }).toList();
  }

  /// Follow a seller and send them a notification
  static Future<void> follow(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    // Insert follow relationship
    await SupabaseService.table('seller_follows').insert({
      'follower_id': userId,
      'seller_id': sellerId,
    });

    // Get follower name
    final follower = await SupabaseService.table('users')
        .select('full_name')
        .eq('id', userId)
        .maybeSingle();

    final followerName = follower?['full_name'] as String? ?? 'Someone';

    // Send in-app notification to the followed user
    try {
      await SupabaseService.table('notifications').insert({
        'user_id': sellerId,
        'title': '$followerName started following you',
        'body': 'You have a new follower!',
        'type': 'new_follower',
        'data': {'follower_id': userId},
      });
    } catch (e) {
      debugPrint('Follow notification failed: $e');
    }
  }

  /// Unfollow a seller
  static Future<void> unfollow(String sellerId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    await SupabaseService.table('seller_follows')
        .delete()
        .eq('follower_id', userId)
        .eq('seller_id', sellerId);
  }

  /// Get all followers of a seller with their email and name
  static Future<List<Map<String, dynamic>>> getFollowers(String sellerId) async {
    final response = await SupabaseService.table('seller_follows')
        .select('follower_id, users!follower_id(full_name, email)')
        .eq('seller_id', sellerId);

    return (response as List).map((row) {
      final user = row['users'] as Map<String, dynamic>?;
      return {
        'id': row['follower_id'] as String,
        'name': user?['full_name'] as String? ?? 'User',
        'email': user?['email'] as String?,
      };
    }).toList();
  }

  /// Notify all followers when a seller lists a new product
  static Future<void> notifyFollowersOfNewProduct({
    required String sellerId,
    required String sellerName,
    required String productId,
    required String productTitle,
    required double productPrice,
    required String? productThumbnail,
  }) async {
    try {
      final followers = await getFollowers(sellerId);
      if (followers.isEmpty) return;

      // Batch insert notifications
      final notifications = followers.map((follower) => {
        'user_id': follower['id'],
        'title': '$sellerName listed a new product',
        'body': productTitle,
        'type': 'new_product',
        'data': {
          'product_id': productId,
          'seller_id': sellerId,
        },
      }).toList();

      await SupabaseService.table('notifications').insert(notifications);

      // Send emails (fire-and-forget, don't block)
      for (final follower in followers) {
        final email = follower['email'] as String?;
        final name = follower['name'] as String? ?? 'User';
        if (email != null && email.isNotEmpty) {
          EmailService.sendNewProductFromFollowedSeller(
            followerEmail: email,
            followerName: name,
            sellerName: sellerName,
            productTitle: productTitle,
            productPrice: productPrice,
            productThumbnail: productThumbnail,
            productId: productId,
          ).catchError((e) {
            debugPrint('Email notification failed for $email: $e');
          });
        }
      }
    } catch (e) {
      debugPrint('Notify followers failed: $e');
    }
  }
}
