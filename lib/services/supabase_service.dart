import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class SupabaseService {
  // Static API (backward compatible)
  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static SupabaseQueryBuilder table(String tableName) => client.from(tableName);
  static SupabaseStorageClient get storage => client.storage;

  // Instance API
  static SupabaseService get instance => _instance;
  static final SupabaseService _instance = SupabaseService._internal();

  SupabaseService._internal();

  GoTrueClient get instanceAuth => client.auth;
  User? get currentUser => client.auth.currentUser;
  SupabaseQueryBuilder from(String tableName) => client.from(tableName);

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
      ),
    );
  }

  /// Call a Cloudflare Worker function via api.instiy.com
  static Future<Map<String, dynamic>> callFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final session = client.auth.currentSession;
    final token = session?.accessToken ?? AppConfig.supabaseAnonKey;

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/functions/v1/$functionName');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': AppConfig.supabaseAnonKey,
      },
      body: body != null ? jsonEncode(body) : null,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      throw Exception('Function call failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET request to a Cloudflare Worker function
  static Future<Map<String, dynamic>> getFunction(String functionName) async {
    final session = client.auth.currentSession;
    final token = session?.accessToken ?? AppConfig.supabaseAnonKey;

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/functions/v1/$functionName');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': AppConfig.supabaseAnonKey,
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      throw Exception('Function call failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
