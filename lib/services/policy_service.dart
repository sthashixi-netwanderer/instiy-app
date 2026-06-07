import 'supabase_service.dart';

class PolicyService {
  static Future<String> getPolicyContent(String policyType) async {
    final response = await SupabaseService.table('policies')
        .select('content')
        .eq('policy_type', policyType)
        .eq('is_active', true)
        .maybeSingle();

    return response?['content'] ?? '';
  }
}
