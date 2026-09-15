import 'supabase_service.dart';
import 'storage_service.dart';
import 'video_service.dart';
import 'email_service.dart';
import '../models/service_model.dart';
import '../models/category_model.dart';

/// Supabase access for the services marketplace: browse queries embed the
/// provider, category and pricing packages; writes are owner-scoped and
/// enforced by RLS.
class ServiceService {
  static const _select = '''
    *,
    provider:users!services_provider_id_fkey(full_name, avatar_url, is_service_provider, suspended, is_verified),
    category:categories(name, slug),
    packages:service_packages(*),
    reviews:service_reviews(rating)
  ''';

  /// Rows requested per Discover page — see [getServicesPage].
  static const int browsePageSize = 20;

  /// Shared browse query: filters plus a deterministic total order. The id
  /// tiebreaker keeps offset pagination stable when two listings share a
  /// created_at — without it a page boundary can drop or repeat a row.
  static Future<List<dynamic>> _fetchRows({
    String? categoryId,
    String? searchQuery,
    String? providerId,
    List<ServiceStatus>? statuses,
    String? institutionName,
    String? tag,
    int? limit,
    int? offset,
  }) async {
    var query = SupabaseService.table('services').select(_select);

    if (providerId != null) {
      query = query.eq('provider_id', providerId);
    } else if (statuses == null) {
      // Browse defaults to published listings only.
      query = query.eq('status', 'active');
    }
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.map((s) => s.name).toList(),
      );
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    if (tag != null && tag.isNotEmpty) {
      query = query.contains('search_tags', [tag]);
    }
    if (institutionName != null && institutionName.isNotEmpty) {
      query = query.or(
        'institution_codes.is.null,institution_codes.eq.{},'
        'institution_codes.cs.{"$institutionName"}',
      );
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      // Match each typed keyword independently (title OR description) so
      // live, as-you-type search keeps surfacing results while more words
      // are being typed.
      final keywords = searchQuery
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .take(5);
      if (keywords.isNotEmpty) {
        query = query.or(
          keywords
              .map((word) => 'title.ilike.%$word%,description.ilike.%$word%')
              .join(','),
        );
      }
    }

    final ordered = query
        .order('created_at', ascending: false)
        .order('id', ascending: false);
    final response = limit != null
        ? await ordered.range(offset ?? 0, (offset ?? 0) + limit - 1)
        : await ordered;
    return response as List<dynamic>;
  }

  /// In browse mode (browsing = true), services whose provider is no longer
  /// an active service provider or is suspended are excluded client-side.
  static List<Service> _mapRows(List<dynamic> rows, {required bool browsing}) {
    return rows
        .where((row) {
          if (browsing) {
            final provider = row['provider'] as Map<String, dynamic>?;
            if (provider != null) {
              if (provider['is_service_provider'] == false) return false;
              if (provider['suspended'] == true) return false;
            }
          }
          return true;
        })
        .map<Service>((row) => Service.fromJson(row))
        .toList();
  }

  /// Browse published services. Signed-out friendly (public read policy).
  /// [institutionName] filters to listings restricted to that institution —
  /// listings with no restriction ("All institutions") always match.
  static Future<List<Service>> getServices({
    String? categoryId,
    String? searchQuery,
    String? providerId,
    List<ServiceStatus>? statuses,
    String? institutionName,
    String? tag,
    int? limit,
    int? offset,
  }) async {
    final rows = await _fetchRows(
      categoryId: categoryId,
      searchQuery: searchQuery,
      providerId: providerId,
      statuses: statuses,
      institutionName: institutionName,
      tag: tag,
      limit: limit,
      offset: offset,
    );
    return _mapRows(rows, browsing: providerId == null);
  }

  /// One page of browse results plus whether the server has rows past it.
  /// The page is probed with limit + 1 rows so [hasMore] reflects the raw
  /// row count — the client-side provider filter in [_mapRows] can otherwise
  /// make a full page look like the end of the list.
  static Future<({List<Service> services, bool hasMore})> getServicesPage({
    String? categoryId,
    String? searchQuery,
    String? institutionName,
    String? tag,
    int limit = browsePageSize,
    int offset = 0,
  }) async {
    final rows = await _fetchRows(
      categoryId: categoryId,
      searchQuery: searchQuery,
      institutionName: institutionName,
      tag: tag,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = rows.length > limit;
    return (
      services: _mapRows(
        hasMore ? rows.sublist(0, limit) : rows,
        browsing: true,
      ),
      hasMore: hasMore,
    );
  }

  /// Active services whose video is featured in the Clips feed (public read,
  /// same shape as [getServices]). Suspended or de-opted provider accounts are
  /// filtered out client-side like browse mode.
  static Future<List<Service>> getClipServices() async {
    final response = await SupabaseService.table('services')
        .select(_select)
        .eq('status', 'active')
        .eq('show_on_clips', true)
        .not('video_urls', 'eq', '{}')
        .order('created_at', ascending: false);
    final rawList = response as List<dynamic>;
    return rawList
        .where((row) {
          final provider = row['provider'] as Map<String, dynamic>?;
          if (provider != null) {
            if (provider['is_service_provider'] == false) return false;
            if (provider['suspended'] == true) return false;
          }
          return true;
        })
        .map<Service>((row) => Service.fromJson(row))
        .toList();
  }

  static Future<Service?> getService(String serviceId) async {
    final response = await SupabaseService.table('services')
        .select(_select)
        .eq('id', serviceId)
        .maybeSingle();
    if (response == null) return null;
    final service = Service.fromJson(response);
    // The bio and public email are fetched separately (and tolerantly)
    // rather than joined so detail pages keep working while their columns'
    // migrations are pending on the hosted database.
    final bio = await getProviderBio(service.providerId);
    final email = await getProviderEmail(service.providerId);
    return service.copyWith(
      providerBio: bio ?? service.providerBio,
      providerPublicEmail: email ?? service.providerPublicEmail,
    );
  }

  /// All listings of the current user (any status) — the "My Services"
  /// dashboard inside the Services screen.
  static Future<List<Service>> getMyServices() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return [];
    return getServices(providerId: userId, statuses: ServiceStatus.values);
  }

  /// Whether the current user has opted in as a service provider and is active.
  static Future<bool> isServiceProvider() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await SupabaseService.table('users')
        .select('is_service_provider, suspended')
        .eq('id', userId)
        .maybeSingle();
    return row?['is_service_provider'] == true && row?['suspended'] != true;
  }

  /// One-way opt-in executed from the Services screen only. Stores the bio
  /// and (optionally) the public contact email. Prefers the two-arg RPC; if
  /// only the service_provider_bio migration is deployed (not the email one
  /// yet) it falls back to the one-arg RPC and then tries a direct email
  /// save, which is a no-op until that column exists.
  static Future<void> becomeServiceProvider(String bio, String? email) async {
    try {
      await SupabaseService.client.rpc(
        'become_service_provider',
        params: {
          'p_bio': bio.trim(),
          'p_email': email?.trim(),
        },
      );
    } catch (_) {
      try {
        await SupabaseService.client.rpc(
          'become_service_provider',
          params: {'p_bio': bio.trim()},
        );
      } catch (_) {
        await SupabaseService.client.rpc('become_service_provider');
      }
      if (email != null && email.trim().isNotEmpty) {
        try {
          await updateServiceProviderEmail(email);
        } catch (_) {}
      }
    }
  }

  /// Best-effort provider bio lookup — returns null (never throws) while
  /// the service_provider_bio migration hasn't been applied yet.
  static Future<String?> getProviderBio(String providerId) async {
    try {
      final row = await SupabaseService.table('users')
          .select('service_provider_bio')
          .eq('id', providerId)
          .maybeSingle();
      return row?['service_provider_bio'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort provider public-email lookup — returns null (never throws)
  /// while the service_provider_email migration hasn't been applied yet.
  static Future<String?> getProviderEmail(String providerId) async {
    try {
      final row = await SupabaseService.table('users')
          .select('service_provider_email')
          .eq('id', providerId)
          .maybeSingle();
      return row?['service_provider_email'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Updates the signed-in provider's marketplace bio. Round-trips the
  /// written row so a filtered-out update (RLS or missing profile) throws
  /// instead of silently reporting success.
  static Future<void> updateServiceProviderBio(String bio) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final rows = await SupabaseService.table('users')
        .update({'service_provider_bio': bio.trim()})
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw Exception('Profile row not found');
  }

  /// Updates the signed-in provider's public contact email. Round-trips the
  /// written row like [updateServiceProviderBio].
  static Future<void> updateServiceProviderEmail(String email) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final trimmed = email.trim();
    final rows = await SupabaseService.table('users')
        .update({
          'service_provider_email':
              trimmed.isEmpty ? null : trimmed,
        })
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw Exception('Profile row not found');
  }

  static Future<List<Category>> getServiceCategories() async {
    final response = await SupabaseService.table('categories')
        .select()
        .eq('type', 'service')
        .order('name');
    return response
        .map<Category>((row) => Category.fromJson(row))
        .toList();
  }

  /// Uploads gallery images to R2 under the services folder.
  static Future<List<String>> uploadServiceImages(
    List<dynamic> images,
  ) async {
    final urls = <String>[];
    for (final image in images) {
      final url = await StorageService.uploadImage(file: image, folder: 'services');
      urls.add(url);
    }
    return urls;
  }

  /// Compresses (trimming to the first 30 seconds) and uploads showcase
  /// videos to R2 under the services folder.
  static Future<List<String>> uploadServiceVideos(
    List<dynamic> videos,
  ) async {
    final urls = <String>[];
    for (var video in videos) {
      video = await VideoService.compressVideo(video);
      final url = await StorageService.uploadFile(
        file: video,
        folder: 'services/videos',
        contentType: 'video/mp4',
        extension: 'mp4',
      );
      urls.add(url);
    }
    return urls;
  }

  static Future<Service> createService({
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
    bool showOnClips = false,
    String? clipVideoUrl,
    List<String> institutionCodes = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final isProvider = await isServiceProvider();
    if (!isProvider) {
      throw Exception('You must be an active service provider to create services.');
    }

    final inserted = await SupabaseService.table('services').insert({
      'provider_id': userId,
      'title': title,
      'description': description,
      'category': categoryName,
      'category_id': categoryId,
      'price': price,
      'price_type': priceType,
      'delivery_days': deliveryDays,
      'image_urls': imageUrls,
      'video_urls': videoUrls,
      'show_on_clips': showOnClips,
      'clip_video_url': clipVideoUrl,
      'institution_codes': institutionCodes,
      'search_tags': searchTags,
      'status': ServiceStatus.active.name,
    }).select('id').single();

    final serviceId = inserted['id'] as String;
    await _savePackages(serviceId, packages);

    final created = await getService(serviceId);
    return created ??
        Service(
          id: serviceId,
          providerId: userId,
          title: title,
          description: description,
          categoryId: categoryId,
          categoryName: categoryName,
          price: price,
          imageUrls: imageUrls,
          videoUrls: videoUrls,
          searchTags: searchTags,
          createdAt: DateTime.now(),
          packages: packages
              .map((p) => p.copyWith(serviceId: serviceId))
              .toList(),
        );
  }

  static Future<void> updateService(
    String serviceId, {
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
    bool showOnClips = false,
    String? clipVideoUrl,
    List<String> institutionCodes = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    final isProvider = await isServiceProvider();
    if (!isProvider) {
      throw Exception('You must be an active service provider to edit services.');
    }

    await SupabaseService.table('services').update({
      'title': title,
      'description': description,
      'category': categoryName,
      'category_id': categoryId,
      'price': price,
      'price_type': priceType,
      'delivery_days': deliveryDays,
      'image_urls': imageUrls,
      'video_urls': videoUrls,
      // Always written (even when null) so turning Clips off clears a
      // previously pinned clip video.
      'show_on_clips': showOnClips,
      'clip_video_url': clipVideoUrl,
      'institution_codes': institutionCodes,
      'search_tags': searchTags,
    }).eq('id', serviceId);

    await _savePackages(serviceId, packages);
  }

  /// Pause (hide from browse) or re-publish a listing.
  static Future<void> setServiceStatus(
    String serviceId,
    ServiceStatus status,
  ) async {
    if (status == ServiceStatus.active) {
      final isProvider = await isServiceProvider();
      if (!isProvider) {
        throw Exception('You must be an active service provider to publish services.');
      }
    }
    await SupabaseService.table('services')
        .update({'status': status.name})
        .eq('id', serviceId);
  }

  static Future<void> deleteService(String serviceId) async {
    await SupabaseService.table('services').delete().eq('id', serviceId);
  }

  /// Replace-then-insert package rows (same pattern as product institution
  /// fees). The price-sync trigger refreshes the service's starting price.
  static Future<void> _savePackages(
    String serviceId,
    List<ServicePackage> packages,
  ) async {
    await SupabaseService.table('service_packages')
        .delete()
        .eq('service_id', serviceId);
    if (packages.isEmpty) return;
    await SupabaseService.table('service_packages').insert(
      packages
          .map((p) => p.toJson(serviceId: serviceId))
          .toList(),
    );
  }

  // ------------------------------------------------------------
  // Reviews
  // ------------------------------------------------------------

  static const _reviewSelect = '''
    *,
    reviewer:users!service_reviews_reviewer_id_fkey(full_name, avatar_url)
  ''';

  static Future<List<ServiceReview>> getServiceReviews(
    String serviceId,
  ) async {
    final response = await SupabaseService.table('service_reviews')
        .select(_reviewSelect)
        .eq('service_id', serviceId)
        .order('created_at', ascending: true);
    final flatList = (response as List<dynamic>)
        .map<ServiceReview>(
          (row) => ServiceReview.fromJson(row as Map<String, dynamic>),
        )
        .toList();

    // Nest replies under their top-level review (mirrors product reviews).
    final Map<String, ServiceReview> reviewMap = {
      for (final r in flatList) r.id: r,
    };
    final topLevel = <ServiceReview>[];
    for (final review in flatList) {
      final parentId = review.parentId;
      if (parentId == null) {
        topLevel.add(review);
      } else {
        final parent = reviewMap[parentId];
        if (parent != null) {
          if (parent.replies.isEmpty) parent.replies = [];
          parent.replies.add(review);
        } else {
          topLevel.add(review);
        }
      }
    }
    return topLevel.reversed.toList();
  }

  static Future<ServiceReview?> getUserServiceReview(
    String serviceId,
    String userId,
  ) async {
    final response = await SupabaseService.table('service_reviews')
        .select(_reviewSelect)
        .eq('service_id', serviceId)
        .eq('reviewer_id', userId)
        .filter('parent_id', 'is', null)
        .maybeSingle();
    return response == null ? null : ServiceReview.fromJson(response);
  }

  /// Creates (or replaces) the current user's top-level review. One per
  /// user per service, enforced by the partial unique index; replies live
  /// in the same table with a parent_id and are unaffected.
  static Future<List<String>> uploadServiceReviewImages(
    List<dynamic> files,
  ) async {
    final urls = <String>[];
    for (final file in files.take(5)) {
      final path = (file as dynamic).path as String;
      final ext = path.split('.').last.toLowerCase();
      urls.add(
        await StorageService.uploadFile(
          file: file,
          folder: 'reviews',
          contentType: 'image/$ext',
          extension: ext,
        ),
      );
    }
    return urls;
  }

  static Future<void> submitServiceReview({
    required String serviceId,
    required String providerId,
    required int rating,
    required String comment,
    List<dynamic> imageFiles = const [],
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final mediaUrls = imageFiles.isNotEmpty
        ? await uploadServiceReviewImages(imageFiles)
        : <String>[];

    // No upsert here: the one-review-per-user rule is a partial unique
    // index (top-level reviews only, so replies stay unlimited), which
    // Postgres rejects as an ON CONFLICT target. Check explicitly instead.
    final existing = await getUserServiceReview(serviceId, userId);
    if (existing != null) {
      await SupabaseService.table('service_reviews').update({
        'rating': rating,
        'comment': comment,
        'media_urls': mediaUrls,
      }).eq('id', existing.id);
    } else {
      await SupabaseService.table('service_reviews').insert({
        'service_id': serviceId,
        'reviewer_id': userId,
        'rating': rating,
        'comment': comment,
        'media_urls': mediaUrls,
      });
    }

    // Notify the provider in-app and by email (mirrors product reviews).
    if (providerId != userId) {
      try {
        final service = await SupabaseService.table('services')
            .select('title')
            .eq('id', serviceId)
            .maybeSingle();
        final reviewer = await SupabaseService.table('users')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        final provider = await SupabaseService.table('users')
            .select('full_name, email')
            .eq('id', providerId)
            .maybeSingle();

        final serviceTitle =
            service?['title'] as String? ?? 'your service';
        final reviewerName =
            reviewer?['full_name'] as String? ?? 'Someone';

        await SupabaseService.client.rpc('create_notification', params: {
          'p_user_id': providerId,
          'p_title': 'New review on your service',
          'p_body': '$reviewerName reviewed "$serviceTitle" — '
              '${'★' * rating}${'☆' * (5 - rating)}',
          'p_type': 'service_review',
          'p_data': {
            'service_id': serviceId,
            'reviewer_id': userId,
            'type': 'service_review',
          },
        });

        final providerEmail = provider?['email'] as String?;
        if (providerEmail != null) {
          await EmailService.sendNewServiceReview(
            providerEmail: providerEmail,
            providerName:
                provider?['full_name'] as String? ?? 'Provider',
            reviewerName: reviewerName,
            serviceTitle: serviceTitle,
            rating: rating,
            comment: comment,
          );
        }
      } catch (_) {}
    }
  }

  static Future<void> updateServiceReview(
    String reviewId, {
    required int rating,
    required String comment,
    List<String>? keepMediaUrls,
    List<dynamic>? newImageFiles,
  }) async {
    final update = <String, dynamic>{
      'rating': rating,
      'comment': comment,
    };
    if (keepMediaUrls != null || newImageFiles != null) {
      final mediaUrls = <String>[...(keepMediaUrls ?? const [])];
      if (newImageFiles != null && newImageFiles.isNotEmpty) {
        final remaining = 5 - mediaUrls.length;
        mediaUrls.addAll(
          await uploadServiceReviewImages(
            newImageFiles.take(remaining.clamp(0, 5)).toList(),
          ),
        );
      }
      update['media_urls'] = mediaUrls.take(5).toList();
    }
    await SupabaseService.table('service_reviews').update(update).eq('id', reviewId);
  }

  static Future<void> deleteServiceReview(String reviewId) async {
    await SupabaseService.table('service_reviews').delete().eq('id', reviewId);
  }

  /// Posts a threaded reply under a top-level review (mirrors product
  /// review replies — replies carry no star rating).
  static Future<void> submitServiceReply({
    required String serviceId,
    required String comment,
    required String parentId,
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await SupabaseService.table('service_reviews').insert({
      'service_id': serviceId,
      'reviewer_id': userId,
      'rating': null,
      'comment': comment,
      'media_urls': <String>[],
      'parent_id': parentId,
    });
  }

  static Future<void> updateServiceReply(String replyId, String reply) async {
    await SupabaseService.table('service_reviews')
        .update({'comment': reply})
        .eq('id', replyId);
  }
}
