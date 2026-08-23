import 'supabase_service.dart';

/// One-way seller opt-in.
///
/// Calls the `become_seller` RPC, which upserts the caller's business
/// profile and sets `users.is_seller = true` in a single transaction.
/// The flag is permanent — there is no client-side way back.
class SellerOnboardingService {
  static Future<void> becomeSeller({
    required String businessName,
    String? description,
  }) async {
    await SupabaseService.client.rpc(
      'become_seller',
      params: {
        'p_business_name': businessName,
        'p_description': description,
      },
    );
  }
}
