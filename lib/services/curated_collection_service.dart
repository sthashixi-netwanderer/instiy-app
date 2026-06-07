import 'dart:isolate';
import '../models/curated_collection_model.dart';
import 'supabase_service.dart';

class CuratedCollectionService {
  /// Fetch all visible curated collections with their items for the home screen
  static Future<List<CuratedCollection>> getHomeSections() async {
    final response = await SupabaseService.client.rpc(
      'get_curated_home_sections',
    );

    // Offload complex nested JSON parsing to background isolate
    return Isolate.run(() => CuratedCollection.parseRpcResponse(response as List));
  }
}
