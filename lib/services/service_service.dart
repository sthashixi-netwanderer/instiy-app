import 'supabase_service.dart';
import 'storage_service.dart';
import 'video_service.dart';
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

    final ordered = query.order('created_at', ascending: false);
    final response = limit != null
        ? await ordered.range(offset ?? 0, (offset ?? 0) + limit - 1)
        : await ordered;
    
    // In browse mode (providerId == null), ensure services whose provider is
    // no longer an active service provider or suspended are excluded.
    final rawList = response as List<dynamic>;
    return rawList
        .where((row) {
          if (providerId == null) {
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
        .order('created_at', ascending: false);
    return response
        .map<ServiceReview>(
          (row) => ServiceReview.fromJson(row),
        )
        .toList();
  }

  static Future<ServiceReview?> getUserServiceReview(
    String serviceId,
    String userId,
  ) async {
    final response = await SupabaseService.table('service_reviews')
        .select(_reviewSelect)
        .eq('service_id', serviceId)
        .eq('reviewer_id', userId)
        .maybeSingle();
    return response == null ? null : ServiceReview.fromJson(response);
  }

  /// Creates (or replaces) the current user's review. The UNIQUE
  /// (service_id, reviewer_id) constraint + upsert keeps one per user.
  static Future<void> submitServiceReview({
    required String serviceId,
    required String providerId,
    required int rating,
    required String comment,
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await SupabaseService.table('service_reviews').upsert(
      {
        'service_id': serviceId,
        'reviewer_id': userId,
        'rating': rating,
        'comment': comment,
      },
      onConflict: 'service_id,reviewer_id',
    );

    // Notify the provider (best-effort, mirrors product reviews).
    if (providerId != userId) {
      try {
        await SupabaseService.table('notifications').insert({
          'user_id': providerId,
          'title': 'New service review',
          'body': 'Someone left a $rating-star review on your service.',
          'type': 'review',
        });
      } catch (_) {}
    }
  }

  static Future<void> updateServiceReview(
    String reviewId, {
    required int rating,
    required String comment,
  }) async {
    await SupabaseService.table('service_reviews').update({
      'rating': rating,
      'comment': comment,
    }).eq('id', reviewId);
  }

  static Future<void> deleteServiceReview(String reviewId) async {
    await SupabaseService.table('service_reviews').delete().eq('id', reviewId);
  }
}
