// Conditional import: web gets stubs, mobile gets real filesystem caching.
export 'media_cache_service_native.dart'
    if (dart.library.js_interop) 'media_cache_service_web.dart';
