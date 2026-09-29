// Conditional import: mobile gets real mic capture, web gets a stub.
export 'call_mic_recorder_native.dart'
    if (dart.library.js_interop) 'call_mic_recorder_stub.dart';
