import 'dart:io';
import 'supabase_service.dart';
import 'storage_service.dart';
import '../models/seller_review_model.dart';
import 'email_service.dart';

class ReviewService {
  static Future<List<ProductReview>> getProductReviews(String productId) async {
    final response = await SupabaseService.table('product_reviews')
        .select('''
          *,
          reviewer:users!reviewer_id(full_name, avatar_url)
        ''')
        .eq('product_id', productId)
        .order('created_at', ascending: true);

    final flatList = (response as List)
        .map((json) => ProductReview.fromJson(json as Map<String, dynamic>))
        .toList();

    final Map<String, ProductReview> reviewMap = {
      for (final r in flatList) r.id: r
    };

    final List<ProductReview> topLevelReviews = [];

    for (final review in flatList) {
      if (review.parentId == null) {
        topLevelReviews.add(review);
      } else {
        final parent = reviewMap[review.parentId];
        if (parent != null) {
          if (parent.replies.isEmpty) {
            parent.replies = [];
          }
          parent.replies.add(review);
        } else {
          topLevelReviews.add(review);
        }
      }
    }

    await _attachSellerReplies(topLevelReviews);

    return topLevelReviews.reversed.toList();
  }

  /// Seller replies live in product_review_replies so buyers see them on the
  /// product page alongside threaded product_reviews replies.
  static Future<void> _attachSellerReplies(
    List<ProductReview> topLevelReviews,
  ) async {
    if (topLevelReviews.isEmpty) return;
    try {
      final ids = topLevelReviews.map((r) => r.id).toList();
      final response = await SupabaseService.table('product_review_replies')
          .select('*, seller:users!seller_id(full_name, avatar_url)')
          .inFilter('review_id', ids);
      for (final raw in (response as List)) {
        final map = Map<String, dynamic>.from(raw as Map);
        final reviewId = map['review_id'] as String?;
        if (reviewId == null) continue;
        final parent = topLevelReviews.firstWhere(
          (r) => r.id == reviewId,
          orElse: () => topLevelReviews.first,
        );
        if (parent.id != reviewId) continue;
        final seller = map['seller'] as Map<String, dynamic>?;
        final createdRaw = map['created_at'] as String?;
        final updatedRaw = map['updated_at'] as String? ?? createdRaw;
        if (createdRaw == null) continue;
        // Skip when a seller reply is already present from another source.
        if (parent.replies.any((r) => r.id == map['id'])) continue;
        parent.replies.add(
          ProductReview(
            id: map['id'] as String,
            productId: parent.productId,
            reviewerId: (map['seller_id'] as String?) ?? '',
            rating: 0,
            comment: map['reply'] as String?,
            mediaUrls: (map['media_urls'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                const [],
            helpfulCount: 0,
            createdAt: DateTime.parse(createdRaw),
            updatedAt: DateTime.parse(updatedRaw!),
            reviewerName: seller?['full_name'] as String? ?? 'Seller',
            reviewerAvatar: seller?['avatar_url'] as String?,
            parentId: reviewId,
          ),
        );
      }
    } catch (_) {}
  }

  static Future<ProductReview?> getUserReview(String productId, String userId) async {
    final response = await SupabaseService.table('product_reviews')
        .select('''
          *,
          reviewer:users!reviewer_id(full_name, avatar_url)
        ''')
        .eq('product_id', productId)
        .eq('reviewer_id', userId)
        .filter('parent_id', 'is', null)
        .maybeSingle();

    if (response == null) return null;
    return ProductReview.fromJson(response);
  }

  static Future<void> submitReview({
    required String productId,
    required String reviewerId,
    required int rating,
    String? comment,
    List<File>? mediaFiles,
  }) async {
    List<String> mediaUrls = [];
    if (mediaFiles != null && mediaFiles.isNotEmpty) {
      for (final file in mediaFiles) {
        final ext = file.path.split('.').last.toLowerCase();
        final isVideo = ['mp4', 'mov', 'avi', 'webm'].contains(ext);
        final url = await StorageService.uploadFile(
          file: file,
          folder: 'reviews',
          contentType: isVideo ? 'video/$ext' : 'image/$ext',
          extension: ext,
        );
        mediaUrls.add(url);
      }
    }

    // Check if user already has a top-level review for this product
    final existing = await SupabaseService.table('product_reviews')
        .select('id')
        .eq('product_id', productId)
        .eq('reviewer_id', reviewerId)
        .filter('parent_id', 'is', null)
        .maybeSingle();

    if (existing != null) {
      // Update existing review
      await SupabaseService.table('product_reviews')
          .update({
            'rating': rating,
            'comment': comment,
            'media_urls': mediaUrls,
          })
          .eq('id', existing['id'] as String);
    } else {
      // Insert new review
      await SupabaseService.table('product_reviews').insert({
        'product_id': productId,
        'reviewer_id': reviewerId,
        'rating': rating,
        'comment': comment,
        'media_urls': mediaUrls,
      });
    }

    // Send email to seller
    try {
      final product = await SupabaseService.table('products')
          .select('seller_id, title')
          .eq('id', productId)
          .maybeSingle();

      if (product != null) {
        final seller = await SupabaseService.table('users')
            .select('full_name, email')
            .eq('id', product['seller_id'])
            .maybeSingle();

        final reviewer = await SupabaseService.table('users')
            .select('full_name')
            .eq('id', reviewerId)
            .maybeSingle();

        if (seller != null && reviewer != null) {
          // In-app notification for the seller
          await SupabaseService.table('notifications').insert({
            'user_id': product['seller_id'],
            'title': 'New review on your product',
            'body': '${reviewer['full_name'] as String? ?? 'Someone'} reviewed "${product['title'] as String? ?? 'your product'}" — ${'★' * rating}${'☆' * (5 - rating)}',
            'type': 'review',
            'data': {
              'product_id': productId,
              'reviewer_id': reviewerId,
            },
          });

          final sellerEmail = seller['email'] as String?;
          if (sellerEmail != null) {
            await EmailService.sendNewReview(
              sellerEmail: sellerEmail,
              sellerName: seller['full_name'] as String? ?? 'Seller',
              reviewerName: reviewer['full_name'] as String? ?? 'Buyer',
              productTitle: product['title'] as String? ?? 'Product',
              rating: rating,
              comment: comment,
            );
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> updateReview({
    required String reviewId,
    required int rating,
    String? comment,
    List<File>? newMediaFiles,
    List<String>? keepMediaUrls,
  }) async {
    final updateData = <String, dynamic>{
      'rating': rating,
      'comment': comment,
    };

    if (newMediaFiles != null || keepMediaUrls != null) {
      List<String> mediaUrls = keepMediaUrls ?? [];

      if (newMediaFiles != null) {
        for (final file in newMediaFiles) {
          final ext = file.path.split('.').last.toLowerCase();
          final isVideo = ['mp4', 'mov', 'avi', 'webm'].contains(ext);
          final url = await StorageService.uploadFile(
            file: file,
            folder: 'reviews',
            contentType: isVideo ? 'video/$ext' : 'image/$ext',
            extension: ext,
          );
          mediaUrls.add(url);
        }
      }

      updateData['media_urls'] = mediaUrls;
    }

    await SupabaseService.table('product_reviews')
        .update(updateData)
        .eq('id', reviewId);
  }

  static Future<void> deleteReview(String reviewId) async {
    await SupabaseService.table('product_reviews')
        .delete()
        .eq('id', reviewId);
  }

  static Future<void> submitReply({
    required String productId,
    required String reviewerId,
    required String comment,
    required String parentId,
  }) async {
    await SupabaseService.table('product_reviews').insert({
      'product_id': productId,
      'reviewer_id': reviewerId,
      'comment': comment,
      'parent_id': parentId,
      'rating': null,
      'media_urls': <String>[],
    });
  }

  static Future<void> updateReply(String replyId, String reply) async {
    await SupabaseService.table('product_reviews')
        .update({'comment': reply})
        .eq('id', replyId);
  }
}
