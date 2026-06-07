import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class SecretsService {
  SecretsService._();

  static final SecretsService _instance = SecretsService._();
  static SecretsService get instance => _instance;

  String? _r2Endpoint;
  String? _r2AccessKeyId;
  String? _r2SecretAccessKey;
  String? _r2BucketName;
  String? _r2PublicUrl;
  String? _paystackPublicKey;
  String? _supabaseRedirectUrl;
  String? _giphyApiKey;
  String? _appVersion;

  String get r2Endpoint =>
      _r2Endpoint ?? 'https://220fcabda76df0d761a0e57dd6d1552f.r2.cloudflarestorage.com';
  String get r2AccessKeyId =>
      _r2AccessKeyId ?? 'da027693b830157291b61dabae737c9c';
  String get r2SecretAccessKey =>
      _r2SecretAccessKey ??
      '150c64eb12aaabc1386a2733cc9f472cc9f54c60ac1fac6c8a10890a03cd273c';
  String get r2BucketName => _r2BucketName ?? 'instiy';
  String get r2PublicUrl => _r2PublicUrl ?? 'https://media.instiy.com';
  String get paystackPublicKey =>
      _paystackPublicKey ??
      'pk_test_87ec8929728da9a3aca5f809886c04ae60270b82';
  String get supabaseRedirectUrl =>
      _supabaseRedirectUrl ?? 'http://localhost:3000';
  String get giphyApiKey =>
      _giphyApiKey ?? 'sXpGFDGZs0Dv1mmNFvYaGUvYwKX0PWIh';
  String get appName => 'Instiy';
  String get appVersion => _appVersion ?? '1.0.0';

  Future<void> initialize() async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'get-secrets',
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return;

      _r2Endpoint = data['r2_endpoint'] as String?;
      _r2AccessKeyId = data['r2_access_key_id'] as String?;
      _r2SecretAccessKey = data['r2_secret_access_key'] as String?;
      _r2BucketName = data['r2_bucket_name'] as String?;
      _r2PublicUrl = data['r2_public_url'] as String?;
      _paystackPublicKey = data['paystack_public_key'] as String?;
      _supabaseRedirectUrl = data['supabase_redirect_url'] as String?;
      _giphyApiKey = data['giphy_api_key'] as String?;
      _appVersion = data['app_version'] as String?;
    } catch (e) {
      debugPrint(
          'SecretsService: Failed to fetch from Edge Function, using local defaults: $e');
    }
  }
}
