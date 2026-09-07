import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Session-scoped cache for chat message images.
///
/// Chat media lives authoritatively on R2 and is fetched on demand. This
/// manager holds only session copies: thumbnails while scrolling and the
/// full image once the user opens it in the viewer. Nothing here is meant
/// to survive logout — [AuthProvider.signOut] empties the store, and the
/// next login re-fetches from R2 on demand.
class ChatMediaCacheManager extends CacheManager {
  /// Repository key — separate on-disk store from the default
  /// "libCachedImageData" cache so emptying it never touches
  /// product/avatar/category artwork.
  static const String repoKey = 'chatMedia';

  static final ChatMediaCacheManager _instance =
      ChatMediaCacheManager._internal();

  /// Singleton — one shared cache store per app run.
  factory ChatMediaCacheManager() => _instance;

  ChatMediaCacheManager._internal()
      : super(Config(
          repoKey,
          stalePeriod: const Duration(days: 3),
          maxNrOfCacheObjects: 200,
        ));
}
