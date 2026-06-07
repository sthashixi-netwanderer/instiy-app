import '../models/institution_model.dart';
import 'supabase_service.dart';

class InstitutionService {
  // Fetch all institutions ordered by name
  static Future<List<Institution>> getInstitutions() async {
    final response = await SupabaseService.table('institutions')
        .select()
        .order('name');

    return (response as List)
        .map((json) => Institution.fromJson(json))
        .toList();
  }

  /// Get institutions with product counts via RPC
  static Future<List<Institution>> getInstitutionsWithCounts() async {
    final response = await SupabaseService.client
        .rpc('get_institution_product_counts');
    return (response as List)
        .map((json) => Institution.fromJson(json))
        .toList();
  }
}
