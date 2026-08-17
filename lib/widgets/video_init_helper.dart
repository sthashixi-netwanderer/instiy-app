// Conditional import: mobile uses cache + dart:io, web uses network only.
export 'video_init_helper_native.dart'
    if (dart.library.js_interop) 'video_init_helper_web.dart';
