import 'dart:async';

// `hide Category` avoids clashing with Flutter's foundation @Category
// annotation — the app's own Category model is what we mean here.
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/category_model.dart';

/// Dedicated persistent [CacheManager] for category artwork.
///
/// Uses its own repository ("categoryImages") so category banners are never
/// evicted by product/avatar churn in the default cache, and a long stale
/// period because admin-managed category artwork rarely changes.
///
/// Result: after the first successful load, category images are served from
/// local disk on every subsequent app start and no requests reach the server
/// until an entry expires (or the admin changes the image URL).
class CategoryImageCacheManager extends CacheManager {
  /// Repository key — creates a separate on-disk store from the default
  /// "libCachedImageData" cache used by product/avatars.
  static const String repoKey = 'categoryImages';

  static final CategoryImageCacheManager _instance =
      CategoryImageCacheManager._internal();

  /// Singleton — one shared cache store per app run.
  factory CategoryImageCacheManager() => _instance;

  CategoryImageCacheManager._internal()
      : super(Config(
          repoKey,
          stalePeriod: const Duration(days: 90),
          maxNrOfCacheObjects: 500,
        ));
}

/// Helpers to pre-warm the persistent category image cache.
class CategoryImageCacheService {
  CategoryImageCacheService._();

  /// URLs already warmed during this app session (dedup guard).
  static final Set<String> _warmedUrls = {};

  /// Fire-and-forget download of every unique category image into
  /// [CategoryImageCacheManager].
  ///
  /// Safe to call repeatedly — each URL is warmed at most once per session,
  /// URLs already fresh on disk cost no network traffic, and all errors are
  /// swallowed (a failed URL may retry on the next load).
  static void warm(List<Category> categories) {
    for (final category in categories) {
      final url = category.imageUrl;
      if (url == null || url.isEmpty || !_warmedUrls.add(url)) continue;
      unawaited(_warmUrl(url));
    }
  }

  static Future<void> _warmUrl(String url) async {
    try {
      await CategoryImageCacheManager().getSingleFile(url);
    } catch (e) {
      // Allow retrying on the next load if warm-up failed.
      _warmedUrls.remove(url);
      debugPrint('CategoryImageCache: warm-up failed for $url: $e');
    }
  }
}
