/// Web stub for MediaCacheService — no filesystem caching on web.
/// All methods return null/false/no-op. Media loads directly from network.
class MediaCacheService {
  MediaCacheService._();

  static Future<dynamic> getCachedFile(String url) async => null;
  static Future<bool> isCached(String url) async => false;
  static Future<dynamic> downloadAndCache(String url) async {
    throw UnsupportedError('MediaCacheService is not available on web');
  }
  static Future<dynamic> getFile(String url) async {
    throw UnsupportedError('MediaCacheService is not available on web');
  }
  static Future<void> precache(String url) async {}
  static Future<dynamic> getFileBackground(String url) async {
    throw UnsupportedError('MediaCacheService is not available on web');
  }
  static Future<void> removeFile(String url) async {}
  static Future<void> clearCache() async {}
  static Future<int> getCacheSize() async => 0;
}
