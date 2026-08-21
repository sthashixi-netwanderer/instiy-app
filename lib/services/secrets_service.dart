import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class SecretsService {
  SecretsService._();

  static final SecretsService _instance = SecretsService._();
  static SecretsService get instance => _instance;

  String? _r2Endpoint;
  String? _r2AccessKeyId;
  String? _r2BucketName;
  String? _r2PublicUrl;
  String? _paystackPublicKey;
  String? _paystackSecretKey;
  String? _supabaseRedirectUrl;
  String? _giphyApiKey;
  String? _appVersion;

  // Safe non-sensitive defaults only. Sensitive keys (R2 access key, Paystack
  // key, Giphy key) have NO hardcoded fallback — callers must await
  // ensureLoaded() before using them. This prevents compiled binaries from
  // containing real credentials that could be extracted via reverse engineering.
  String get r2Endpoint =>
      _r2Endpoint ?? 'https://220fcabda76df0d761a0e57dd6d1552f.r2.cloudflarestorage.com';
  // No hardcoded fallback — must be fetched from remote secrets.
  String get r2AccessKeyId => _r2AccessKeyId ?? '';
  String get r2BucketName => _r2BucketName ?? 'instiy';
  String get r2PublicUrl => _r2PublicUrl ?? 'https://media.instiy.com';
  // No hardcoded fallback — must be fetched from remote secrets.
  String get paystackPublicKey => _paystackPublicKey ?? '';
  // Client-side checkout key for pay_with_paystack. Only served by the
  // worker to authenticated requests, so the first anonymous startup fetch
  // returns it empty — callers refresh after login (see [refresh]).
  // No hardcoded fallback.
  String get paystackSecretKey => _paystackSecretKey ?? '';
  String get supabaseRedirectUrl =>
      _supabaseRedirectUrl ?? 'http://localhost:3000';
  // No hardcoded fallback — must be fetched from remote secrets.
  String get giphyApiKey => _giphyApiKey ?? '';
  String get appName => 'Instiy';
  String get appVersion => _appVersion ?? '1.0.0';

  /// Whether the remote secrets have been fetched at least once.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  /// In-flight fetch, so concurrent callers share one network request.
  Future<void>? _inFlight;

  /// Fetch remote secret overrides. Idempotent and safe to call multiple
  /// times: concurrent calls share the same in-flight request, and once
  /// loaded successfully it short-circuits. Never throws — on failure the
  /// local defaults remain in effect.
  Future<void> initialize() {
    if (_loaded) return Future.value();
    return _inFlight ??= _fetch();
  }

  /// Await this from code paths that genuinely require the remote secrets
  /// (R2 uploads, Paystack checkout, Giphy). If a fetch is already in flight
  /// it is awaited; otherwise a new one is started. Falls back to local
  /// defaults if the fetch fails.
  Future<void> ensureLoaded() => initialize();

  /// Force a fresh fetch, discarding the cached values. Used before Paystack
  /// checkout: the key is only returned once the request carries a user JWT,
  /// which the anonymous startup fetch does not have.
  Future<void> refresh() {
    _loaded = false;
    return initialize();
  }

  Future<void> _fetch() async {
    try {
      final data = await SupabaseService.callFunction('get-secrets');

      _r2Endpoint = data['r2_endpoint'] as String?;
      _r2AccessKeyId = data['r2_access_key_id'] as String?;
      _r2BucketName = data['r2_bucket_name'] as String?;
      _r2PublicUrl = data['r2_public_url'] as String?;
      _paystackPublicKey = data['paystack_public_key'] as String?;
      _paystackSecretKey = data['paystack_secret_key'] as String?;
      _supabaseRedirectUrl = data['supabase_redirect_url'] as String?;
      _giphyApiKey = data['giphy_api_key'] as String?;
      _appVersion = data['app_version'] as String?;
      _loaded = true;
    } catch (e) {
      debugPrint(
          'SecretsService: Failed to fetch from Edge Function, using local defaults: $e');
    } finally {
      _inFlight = null;
    }
  }
}
