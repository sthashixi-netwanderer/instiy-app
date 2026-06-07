import 'package:supabase_flutter/supabase_flutter.dart';
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
}
